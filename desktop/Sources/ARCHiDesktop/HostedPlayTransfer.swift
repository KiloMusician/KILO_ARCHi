import Foundation
import CryptoKit

enum HostedPlayDestinationStamp: Equatable {
    case absent
    case regular(byteCount: Int, sha256: String, inode: UInt64, modified: Date)
}

enum HostedPlayTransferError: LocalizedError {
    case destinationChanged, invalidFile
    var errorDescription: String? {
        switch self {
        case .destinationChanged: "The destination changed after approval. Nothing was replaced; choose another filename."
        case .invalidFile: "Choose a regular JSON file no larger than 2 MB."
        }
    }
}

enum HostedPlayTransfer {
    static let maximumBytes = 2 * 1024 * 1024

    static func captureDestination(_ url: URL) throws -> HostedPlayDestinationStamp {
        guard url.isFileURL, url.pathExtension.lowercased() == "json" else { throw HostedPlayTransferError.invalidFile }
        let before: [FileAttributeKey: Any]
        do { before = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return .absent }
        guard before[.type] as? FileAttributeType == .typeRegular,
              let size = before[.size] as? NSNumber, size.intValue <= maximumBytes,
              let inode = before[.systemFileNumber] as? NSNumber,
              let modified = before[.modificationDate] as? Date else { throw HostedPlayTransferError.invalidFile }
        let data = try readBounded(url)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        guard after[.type] as? FileAttributeType == .typeRegular,
              (after[.systemFileNumber] as? NSNumber)?.uint64Value == inode.uint64Value,
              after[.modificationDate] as? Date == modified,
              (after[.size] as? NSNumber)?.intValue == data.count, size.intValue == data.count else {
            throw HostedPlayTransferError.destinationChanged
        }
        return .regular(byteCount: data.count, sha256: digest(data), inode: inode.uint64Value, modified: modified)
    }

    static func finish(source: URL, destination: URL, approved: HostedPlayDestinationStamp) throws -> HostedPlayDownloadReceipt {
        let bytes = try readBounded(source)
        guard !bytes.isEmpty, (try JSONSerialization.jsonObject(with: bytes)) is [String: Any] else { throw HostedPlayTransferError.invalidFile }
        guard try captureDestination(destination) == approved else { throw HostedPlayTransferError.destinationChanged }
        if approved == .absent {
            // Atomic no-clobber publication: a file created after the check makes
            // the hard link fail instead of being silently overwritten.
            let stage = destination.deletingLastPathComponent().appendingPathComponent(".archi-copy-\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: stage) }
            try bytes.write(to: stage, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.path)
            do { try FileManager.default.linkItem(at: stage, to: destination) }
            catch { throw HostedPlayTransferError.destinationChanged }
        } else {
            // Revalidate immediately before an atomic replacement. This catches
            // delayed destination edits; it is not filesystem-wide atomic CAS
            // against non-cooperating writers in the final check/write interval.
            guard try captureDestination(destination) == approved else { throw HostedPlayTransferError.destinationChanged }
            try bytes.write(to: destination, options: .atomic)
        }
        guard try readBounded(destination) == bytes else { throw HostedPlayTransferError.invalidFile }
        return HostedPlayDownloadReceipt(filename: destination.lastPathComponent, byteCount: bytes.count, sha256: digest(bytes))
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw HostedPlayTransferError.invalidFile }
        return data
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
