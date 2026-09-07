import Foundation
import Network

enum HostedPlayProfile: String, CaseIterable, Sendable {
    case preview, review, acceptance
    var port: UInt16 {
        switch self { case .preview: 43821; case .review: 43822; case .acceptance: 43823 }
    }
    var dataStoreIdentifier: UUID {
        let value: String
        switch self {
        case .preview: value = "1E51CD6D-9007-4C3D-B4A1-5B2E2CD57B01"
        case .review: value = "69AAB431-38C1-44FA-8942-222F49AD1E1C"
        case .acceptance: value = "E915B629-5C72-4AB3-8E6E-657C7D431AB4"
        }
        return UUID(uuidString: value)!
    }
    var origin: URL { URL(string: "http://127.0.0.1:\(port)")! }
    static var current: Self { Bundle.main.bundleIdentifier == "com.quotient.archi.desktop.review" ? .review : .preview }
}

enum HostedPlayError: LocalizedError {
    case missingAssets, invalidAssets, invalidRequest, occupiedPort, stopped, invalidProjection, invalidDownload
    var errorDescription: String? {
        switch self {
        case .missingAssets: "The bundled Habitat is missing. Rebuild this app with its Play resources."
        case .invalidAssets: "The bundled Habitat did not pass its local asset checks."
        case .invalidRequest: "The local asset request was rejected."
        case .occupiedPort: "The Habitat's reserved local port is unavailable. This app will not connect to another server. Close the other copy using this profile and retry."
        case .stopped: "The native Habitat has stopped."
        case .invalidProjection: "A progress message did not match the current native Habitat session."
        case .invalidDownload: "The Journey copy was not a bounded JSON file. Nothing was saved to the chosen destination."
        }
    }
}

struct HostedPlayAsset: Sendable {
    let bytes: Data
    let mimeType: String
}

struct HostedPlayAssets: Sendable {
    static let maximumAssetBytes = 8 * 1024 * 1024
    static let maximumTotalBytes = 32 * 1024 * 1024
    let entries: [String: HostedPlayAsset]

    init(directory: URL) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard let iterator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { throw HostedPlayError.missingAssets }
        var result: [String: HostedPlayAsset] = [:], total = 0
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                     "css": "text/css; charset=utf-8", "png": "image/png", "svg": "image/svg+xml",
                     "webmanifest": "application/manifest+json", "woff2": "font/woff2", "ico": "image/x-icon"]
        for case let file as URL in iterator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw HostedPlayError.invalidAssets }
            guard values.isRegularFile == true else { continue }
            let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root.path + "/"), result.count < 128,
                  let size = values.fileSize, size <= Self.maximumAssetBytes,
                  let mime = types[file.pathExtension.lowercased()] else { throw HostedPlayError.invalidAssets }
            let path = String(resolved.path.dropFirst(root.path.count))
            // Native hosting has no service worker or remote executable surface.
            guard !path.contains("service-worker"), !path.contains("\\"),
                  path == "/index.html" || path.hasPrefix("/assets/") || path.hasPrefix("/pwa/") else {
                throw HostedPlayError.invalidAssets
            }
            let handle = try FileHandle(forReadingFrom: resolved)
            let bytes: Data
            do { bytes = try handle.read(upToCount: Self.maximumAssetBytes + 1) ?? Data(); try handle.close() }
            catch { try? handle.close(); throw error }
            total += bytes.count
            guard bytes.count == size, total <= Self.maximumTotalBytes else { throw HostedPlayError.invalidAssets }
            result[path] = HostedPlayAsset(bytes: bytes, mimeType: mime)
        }
        guard let index = result["/index.html"], let html = String(data: index.bytes, encoding: .utf8),
              html.contains("/assets/"), !html.contains("/@vite/client") else { throw HostedPlayError.missingAssets }
        entries = result
    }

    func response(to request: Data, authority: String) -> Data {
        do {
            let parsed = try HostedPlayRequest.parse(request, authority: authority)
            guard let asset = entries[parsed.path] else { return Self.response(status: "404 Not Found", body: Data()) }
            return Self.response(status: "200 OK", body: asset.bytes, mime: asset.mimeType, head: parsed.head)
        } catch { return Self.response(status: "400 Bad Request", body: Data()) }
    }

    private static func response(status: String, body: Data, mime: String = "text/plain", head: Bool = false) -> Data {
        let csp = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; worker-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; media-src 'none'"
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nCross-Origin-Resource-Policy: same-origin\r\nPermissions-Policy: camera=(), microphone=(), geolocation=(), display-capture=()\r\nContent-Security-Policy: \(csp)\r\n\r\n"
        return Data(headers.utf8) + (head ? Data() : body)
    }
}

struct HostedPlayRequest: Equatable {
    let path: String
    let head: Bool
    static func parse(_ data: Data, authority: String) throws -> Self {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8), text.hasSuffix("\r\n\r\n") else { throw HostedPlayError.invalidRequest }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].components(separatedBy: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(first[0]), first[2] == "HTTP/1.1",
              first[1].hasPrefix("/"), !first[1].hasPrefix("//"), !first[1].contains("#"),
              let decoded = first[1].components(separatedBy: "?")[0].removingPercentEncoding,
              !decoded.contains("\\"), !decoded.contains("\0"), !decoded.contains("%"),
              !decoded.components(separatedBy: "/").contains(where: { $0 == "." || $0 == ".." }),
              !first[1].lowercased().contains("%2f") else { throw HostedPlayError.invalidRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw HostedPlayError.invalidRequest }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw HostedPlayError.invalidRequest }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["host"] == authority, headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == "0",
              headers["origin"] == nil || headers["origin"] == "http://" + authority else { throw HostedPlayError.invalidRequest }
        return Self(path: decoded == "/" ? "/index.html" : decoded, head: first[0] == "HEAD")
    }
}

@MainActor
final class HostedPlayAssetServer {
    var onFailure: ((String) -> Void)?
    private let assets: HostedPlayAssets
    private let port: UInt16
    private var listener: NWListener?
    private var startWaiter: CheckedContinuation<URL, any Error>?
    private var startupTimeout: Task<Void, Never>?
    private var hasStarted = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private struct Client {
        let connection: NWConnection
        var bytes = Data()
        let timeout: Task<Void, Never>
    }
    private var clients: [UUID: Client] = [:]

    init(assets: HostedPlayAssets, port: UInt16) { self.assets = assets; self.port = port }

    func start() async throws -> URL {
        guard listener == nil else { throw HostedPlayError.occupiedPort }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.startupTimeout?.cancel(); self.startupTimeout = nil
                    guard listener.port?.rawValue == self.port else {
                        self.startWaiter?.resume(throwing: HostedPlayError.occupiedPort); self.startWaiter = nil
                        listener.cancel(); return
                    }
                    self.hasStarted = true
                    self.startWaiter?.resume(returning: URL(string: "http://127.0.0.1:\(self.port)/")!)
                    self.startWaiter = nil
                case .failed:
                    self.startupTimeout?.cancel(); self.startupTimeout = nil
                    if self.hasStarted { self.onFailure?("The managed Habitat asset server stopped. Retry to restart it.") }
                    self.startWaiter?.resume(throwing: HostedPlayError.occupiedPort); self.startWaiter = nil
                    listener.cancel()
                case .cancelled:
                    self.startupTimeout?.cancel(); self.startupTimeout = nil
                    self.startWaiter?.resume(throwing: HostedPlayError.stopped); self.startWaiter = nil
                    self.listener = nil
                    for waiter in self.stopWaiters { waiter.resume() }; self.stopWaiters = []
                default: break
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            startWaiter = continuation
            startupTimeout = Task { [weak self, weak listener] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, let listener, self.listener === listener, self.startWaiter != nil else { return }
                self.startWaiter?.resume(throwing: HostedPlayError.occupiedPort); self.startWaiter = nil
                listener.cancel()
            }
            listener.start(queue: .main)
        }
    }

    func shutdown() async {
        for id in Array(clients.keys) { close(id) }
        guard let listener else { return }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
            listener.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, clients.count < 16 else { connection.cancel(); return }
        let id = UUID()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.close(id)
        }
        clients[id] = Client(connection: connection, timeout: timeout)
        connection.start(queue: .main)
        receive(id)
    }

    private func receive(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8193) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, var current = self.clients[id] else { return }
                if let data { current.bytes.append(data) }
                self.clients[id] = current
                guard current.bytes.count <= 8192, error == nil else { self.close(id); return }
                if current.bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let response = self.assets.response(to: current.bytes, authority: "127.0.0.1:\(self.port)")
                    current.connection.send(content: response, completion: .contentProcessed { [weak self] _ in
                        Task { @MainActor in self?.close(id) }
                    })
                } else if complete { self.close(id) }
                else { self.receive(id) }
            }
        }
    }

    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timeout.cancel(); client.connection.cancel()
    }
}
