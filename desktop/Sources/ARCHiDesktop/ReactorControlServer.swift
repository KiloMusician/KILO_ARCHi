import Darwin
import Foundation

/// Local control of the app-owned expression session. This is not a Reactor provider client.
@MainActor
final class ReactorControlServer {
    enum Profile: String, CaseIterable { case review, preview }
    enum ControlError: Error, LocalizedError {
        case unsafeDirectory, unsafeSocket, alreadyRunning, socketFailure, invalidPath
        var errorDescription: String? {
            switch self {
            case .unsafeDirectory: "The local expression control directory is not private and owned by this user."
            case .unsafeSocket: "The local expression control socket cannot be safely replaced."
            case .alreadyRunning: "Another ARCHi expression control server owns this profile."
            case .socketFailure: "The local expression control socket could not start."
            case .invalidPath: "The local expression control socket path is too long."
            }
        }
    }

    nonisolated static let maximumMessageBytes = 256 * 1024
    nonisolated static let allowedActions: Set<String> = ["status", "prepare", "preview", "stop"]
    let socketURL: URL
    private let directoryURL: URL
    private let handler: @MainActor ([String: Any]) -> [String: Any]
    private var listener: DispatchSourceRead?
    private var lockFD: Int32 = -1
    private var clients: Set<Int32> = []
    private var generation = UUID()
    private var socketIdentity: (dev_t, ino_t)?

    init(profile: Profile, directoryURL: URL? = nil,
         handler: @escaping @MainActor ([String: Any]) -> [String: Any]) {
        self.directoryURL = directoryURL ?? URL(fileURLWithPath: "/private/tmp/archi-reactor-\(getuid())-\(profile.rawValue)", isDirectory: true)
        self.socketURL = self.directoryURL.appendingPathComponent("control.sock")
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        try prepareDirectory()
        let acquiredLock = Darwin.open(directoryURL.appendingPathComponent("control.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard acquiredLock >= 0 else { throw ControlError.unsafeDirectory }
        var lockInfo = stat()
        guard fstat(acquiredLock, &lockInfo) == 0, lockInfo.st_uid == getuid(),
              lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_mode & 0o777 == 0o600,
              lockInfo.st_nlink == 1 else {
            close(acquiredLock); throw ControlError.unsafeDirectory
        }
        guard flock(acquiredLock, LOCK_EX | LOCK_NB) == 0 else {
            close(acquiredLock); throw ControlError.alreadyRunning
        }
        lockFD = acquiredLock
        var fd: Int32 = -1
        do {
            var old = stat()
            if lstat(socketURL.path, &old) == 0 {
                // An exclusive profile lock permits recovery of this user's stale socket only.
                guard old.st_uid == getuid(), old.st_mode & S_IFMT == S_IFSOCK,
                      old.st_nlink == 1 else { throw ControlError.unsafeSocket }
                guard unlink(socketURL.path) == 0 else { throw ControlError.unsafeSocket }
            } else if errno != ENOENT { throw ControlError.unsafeSocket }
            fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw ControlError.socketFailure }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = Array(socketURL.path.utf8CString)
            guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlError.invalidPath }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                for (index, byte) in path.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
            }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw ControlError.socketFailure }
            var created = stat()
            guard lstat(socketURL.path, &created) == 0 else { throw ControlError.socketFailure }
            socketIdentity = (created.st_dev, created.st_ino)
            guard chmod(socketURL.path, mode_t(0o600)) == 0, Darwin.listen(fd, 8) == 0,
                  fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw ControlError.socketFailure }
            generation = UUID()
            let listenerFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.acceptAvailable(listenerFD) }
            }
            source.setCancelHandler { close(listenerFD) }
            listener = source
            source.resume()
        } catch {
            if fd >= 0 { close(fd) }
            removeOwnedSocket()
            releaseLock()
            throw error
        }
    }

    func stop() {
        generation = UUID()
        listener?.cancel()
        listener = nil
        for fd in clients { _ = shutdown(fd, SHUT_RDWR) }
        removeOwnedSocket()
        releaseLock()
    }

    private func prepareDirectory() throws {
        if mkdir(directoryURL.path, mode_t(0o700)) != 0 && errno != EEXIST { throw ControlError.unsafeDirectory }
        var info = stat()
        guard lstat(directoryURL.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            throw ControlError.unsafeDirectory
        }
    }

    private func removeOwnedSocket() {
        guard let identity = socketIdentity else { return }
        var info = stat()
        if lstat(socketURL.path, &info) == 0, info.st_uid == getuid(),
           info.st_mode & S_IFMT == S_IFSOCK, info.st_dev == identity.0, info.st_ino == identity.1 {
            _ = unlink(socketURL.path)
        }
        socketIdentity = nil
    }

    private func releaseLock() {
        if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }

    private func acceptAvailable(_ listenerFD: Int32) {
        guard listener != nil else { return }
        // Bound work per main-run-loop callback, including same-user clients that stall.
        for _ in 0..<16 {
            let fd = Darwin.accept(listenerFD, nil, nil)
            if fd < 0 { break }
            var uid = uid_t(), gid = gid_t()
            guard clients.count < 16, getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd); continue
            }
            // Darwin can inherit O_NONBLOCK from the listener. A client may connect
            // before writing its request; the detached reader uses a bounded wait.
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
                close(fd); continue
            }
            clients.insert(fd)
            let requestGeneration = generation
            Task.detached { [weak self] in
                defer { close(fd) }
                Self.setTimeouts(fd)
                let request = Self.readMessage(fd)
                let response = await self?.respond(to: request, generation: requestGeneration)
                    ?? Self.errorData("The ARCHi expression owner is unavailable.")
                Self.writeMessage(response, to: fd)
                await self?.finishedClient(fd)
            }
        }
    }

    private func finishedClient(_ fd: Int32) { clients.remove(fd) }

    private func respond(to data: Data?, generation requestGeneration: UUID) -> Data {
        guard listener != nil, requestGeneration == generation else {
            return Self.errorData("This expression control request has expired.")
        }
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["action"], let action = object["action"] as? String,
              Self.allowedActions.contains(action) else {
            return Self.errorData("Expected one local action: status, prepare, preview, or stop. Credentials and live-start requests are not accepted.")
        }
        let result = handler(["action": action])
        guard Self.containsNoCredentials(result), JSONSerialization.isValidJSONObject(result),
              let encoded = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              encoded.count < Self.maximumMessageBytes else {
            return Self.errorData("The expression owner returned an invalid or private response.")
        }
        return encoded
    }

    nonisolated private static func containsNoCredentials(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            let forbidden: Set<String> = ["apikey", "token", "accesstoken", "refreshtoken", "secret", "credential", "credentials", "authorization", "password", "cookie"]
            return dictionary.allSatisfy { key, value in
                let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
                return !forbidden.contains(normalized) && containsNoCredentials(value)
            }
        }
        if let array = value as? [Any] { return array.allSatisfy(containsNoCredentials) }
        return true
    }

    nonisolated private static func errorData(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message])) ?? Data("{\"ok\":false}".utf8)
    }

    nonisolated private static func setTimeouts(_ fd: Int32) {
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    }

    nonisolated private static func readMessage(_ fd: Int32) -> Data? {
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maximumMessageBytes {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximumMessageBytes + 1 - data.count))
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
            if let newline = data.firstIndex(of: 10) {
                guard data.count <= maximumMessageBytes,
                      data[data.index(after: newline)...].allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 == 32 }) else { return nil }
                return Data(data[..<newline])
            }
        }
        return nil
    }

    nonisolated private static func writeMessage(_ data: Data, to fd: Int32) {
        let message = data + Data([10])
        message.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: sent), buffer.count - sent)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { return }
                sent += count
            }
        }
    }
}
