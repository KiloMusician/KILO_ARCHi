import XCTest
@testable import ARCHiDesktop

final class HostedPlayTests: XCTestCase {
    func testProfilesKeepStableSeparateOriginsAndPersistentStoreIdentifiers() {
        XCTAssertEqual(HostedPlayProfile.preview.port, 43821)
        XCTAssertEqual(HostedPlayProfile.review.port, 43822)
        XCTAssertNotEqual(HostedPlayProfile.preview.dataStoreIdentifier, HostedPlayProfile.review.dataStoreIdentifier)
        XCTAssertEqual(HostedPlayProfile.review.dataStoreIdentifier, HostedPlayProfile.review.dataStoreIdentifier)
        XCTAssertNotEqual(HostedPlayProfile.review.dataStoreIdentifier, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    func testDocumentAndBlobNavigationAreLimitedToExactOwnedOrigin() {
        let profile = HostedPlayProfile.review
        for path in ["/", "/index.html", "/?native=1", "/#habitat"] {
            XCTAssertTrue(HostedPlayNavigation.allowsDocument(URL(string: "http://127.0.0.1:43822" + path), profile: profile))
        }
        for url in ["http://127.0.0.1:43821/", "http://localhost:43822/", "https://127.0.0.1:43822/",
                    "http://127.0.0.1:43822.evil.test/", "http://user@127.0.0.1:43822/", "file:///tmp/index.html",
                    "http://127.0.0.1:43822/assets/index.js", "data:text/html,hello", "about:blank"] {
            XCTAssertFalse(HostedPlayNavigation.allowsDocument(URL(string: url), profile: profile), url)
        }
        XCTAssertTrue(HostedPlayNavigation.allowsDownload(URL(string: "blob:http://127.0.0.1:43822/\(UUID().uuidString)"), profile: profile))
        for url in ["blob:http://127.0.0.1:43821/id", "blob:https://evil.test/id", "blob:null/id", "http://127.0.0.1:43822/copy.json"] {
            XCTAssertFalse(HostedPlayNavigation.allowsDownload(URL(string: url), profile: profile), url)
        }
    }

    func testHTTPAssetContractRequiresExactAuthorityMethodAndCanonicalPaths() throws {
        XCTAssertEqual(try HostedPlayRequest.parse(request("GET /?host=native HTTP/1.1"), authority: authority), HostedPlayRequest(path: "/index.html", head: false))
        XCTAssertEqual(try HostedPlayRequest.parse(request("HEAD /assets/app.js HTTP/1.1"), authority: authority), HostedPlayRequest(path: "/assets/app.js", head: true))
        for line in ["POST / HTTP/1.1", "GET / HTTP/1.0", "GET http://127.0.0.1:43822/ HTTP/1.1",
                     "GET //elsewhere/ HTTP/1.1", "GET /../secret HTTP/1.1", "GET /%2e%2e/secret HTTP/1.1",
                     "GET /assets%2fapp.js HTTP/1.1", "GET /%252e%252e/secret HTTP/1.1", "GET /a\\b HTTP/1.1"] {
            XCTAssertThrowsError(try HostedPlayRequest.parse(request(line), authority: authority), line)
        }
        for extra in ["Host: elsewhere\r\n", "Transfer-Encoding: chunked\r\n", "Content-Length: 20\r\n", "Origin: https://elsewhere.test\r\n"] {
            XCTAssertThrowsError(try HostedPlayRequest.parse(request("GET / HTTP/1.1", extra: extra), authority: authority))
        }
        XCTAssertThrowsError(try HostedPlayRequest.parse(Data(repeating: 65, count: 8193), authority: authority))
    }

    func testEveryFullNavigationRotatesSessionIncludingSameURLButHashOnlyDoesNot() {
        let url = URL(string: "http://127.0.0.1:43822/")!
        let hash = URL(string: "http://127.0.0.1:43822/#habitat")!
        XCTAssertTrue(HostedPlayNavigation.requiresNewSession(from: nil, to: url, isReload: false))
        XCTAssertTrue(HostedPlayNavigation.requiresNewSession(from: url, to: url, isReload: false),
                      "location.assign(location.href) creates a new document even with WK navigation type other")
        XCTAssertTrue(HostedPlayNavigation.requiresNewSession(from: url, to: url, isReload: true))
        XCTAssertFalse(HostedPlayNavigation.requiresNewSession(from: url, to: hash, isReload: false))
        XCTAssertFalse(HostedPlayNavigation.requiresNewSession(from: hash, to: url, isReload: false))
        XCTAssertTrue(HostedPlayNavigation.requiresNewSession(from: hash, to: hash, isReload: true))
    }

    func testBundledAssetsProduceStrictResponsesAndNeverFallbackUnknownFiles() throws {
        let directory = try assetsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try HostedPlayAssets(directory: directory)
        let output = String(decoding: assets.response(to: request("GET / HTTP/1.1"), authority: authority), as: UTF8.self)
        XCTAssertTrue(output.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(output.contains("Content-Security-Policy:"))
        XCTAssertTrue(output.contains("worker-src 'none'"))
        XCTAssertTrue(output.contains("Cache-Control: no-store"))
        XCTAssertTrue(output.contains("camera=(), microphone=()"))
        let missing = String(decoding: assets.response(to: request("GET /unbundled.js HTTP/1.1"), authority: authority), as: UTF8.self)
        XCTAssertTrue(missing.hasPrefix("HTTP/1.1 404 Not Found"))
        let head = String(decoding: assets.response(to: request("HEAD /assets/app.js HTTP/1.1"), authority: authority), as: UTF8.self)
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
        XCTAssertFalse(head.contains("console.log"))
    }

    func testManifestRejectsServiceWorkersSymlinksUnboundedFilesAndDevelopmentHTML() throws {
        for kind in ["service-worker", "symlink", "oversize", "development"] {
            let directory = try assetsDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            switch kind {
            case "service-worker": try Data("self.addEventListener('fetch', () => {})".utf8).write(to: directory.appendingPathComponent("service-worker.js"))
            case "symlink":
                try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("assets/linked.js"), withDestinationURL: directory.appendingPathComponent("assets/app.js"))
            case "oversize":
                try Data(repeating: 65, count: HostedPlayAssets.maximumAssetBytes + 1).write(to: directory.appendingPathComponent("assets/large.js"))
            default: try Data("<script src='/@vite/client'></script>".utf8).write(to: directory.appendingPathComponent("index.html"))
            }
            XCTAssertThrowsError(try HostedPlayAssets(directory: directory), kind)
        }
    }

    func testProjectionRequiresCurrentSessionStrictShapeAndIncreasingTransportSequence() throws {
        let session = UUID()
        let initial = try HostedPlayProjection.decode(projection(session: session), sessionID: session, after: 0)
        XCTAssertEqual(initial.journeyId, "journey-1")
        XCTAssertEqual(initial.revision, "journey-1:8:event-8")
        XCTAssertEqual(initial.eventCount, 8)
        XCTAssertThrowsError(try HostedPlayProjection.decode(projection(session: session), sessionID: session, after: 1))
        XCTAssertThrowsError(try HostedPlayProjection.decode(projection(session: UUID()), sessionID: session, after: 0))
        for key in ["applyEvent", "permission", "sourceText", "request"] {
            var body = projection(session: session); body[key] = "not allowed"
            XCTAssertThrowsError(try HostedPlayProjection.decode(body, sessionID: session, after: 0))
        }
        for value in [true, -1, 0, 1.5] as [Any] {
            var body = projection(session: session); body["sequence"] = value
            XCTAssertThrowsError(try HostedPlayProjection.decode(body, sessionID: session, after: 0))
        }
    }

    func testExplicitRewindProjectionMayReduceEventCountAndChangeIdentity() throws {
        let session = UUID()
        let old = try HostedPlayProjection.decode(projection(session: session), sessionID: session, after: 0)
        var rewind = projection(session: session)
        rewind["sequence"] = 2; rewind["eventCount"] = 0
        rewind["journeyId"] = "journey-restored"; rewind["revision"] = "journey-restored:0:origin"
        let new = try HostedPlayProjection.decode(rewind, sessionID: session, after: old.sequence)
        XCTAssertEqual(new.eventCount, 0)
        XCTAssertEqual(new.journeyId, "journey-restored")
        XCTAssertThrowsError(try HostedPlayProjection.decode(projection(session: session), sessionID: session, after: new.sequence))
    }

    func testRelayUsesExistingReadOnlyProjectionContractWithoutAdditionalFields() throws {
        let session = UUID()
        var body = projection(session: session)
        body["mode"] = "relay"
        let value = try HostedPlayProjection.decode(body, sessionID: session, after: 0)
        XCTAssertEqual(value.mode, .relay)
        XCTAssertEqual(value.eventCount, 8)
        XCTAssertEqual(value.revision, "journey-1:8:event-8")
        body["relayAction"] = "apply"
        XCTAssertThrowsError(try HostedPlayProjection.decode(body, sessionID: session, after: 0))
        body.removeValue(forKey: "relayAction")
        body["mode"] = "unknown-game"
        XCTAssertThrowsError(try HostedPlayProjection.decode(body, sessionID: session, after: 0))
    }

    func testRetiredPageCannotDeclareRecoveryAndNewSessionRejectsOldMessages() throws {
        var gate = HostedPlayProjectionGate()
        gate.begin()
        let oldSession = gate.sessionID
        let original = projection(session: oldSession)
        XCTAssertEqual(try gate.receive(original).readiness, .ready)
        gate.retire()
        var lateReady = original; lateReady["sequence"] = 2
        XCTAssertThrowsError(try gate.receive(lateReady), "Loaded-page metadata cannot erase a native server/page failure")
        gate.begin()
        XCTAssertNotEqual(gate.sessionID, oldSession)
        XCTAssertThrowsError(try gate.receive(lateReady))
        XCTAssertEqual(try gate.receive(projection(session: gate.sessionID)).sequence, 1)
    }

    func testProjectionLoadingAndBoundsDoNotPretendThatStateIsReady() throws {
        let session = UUID()
        var loading = projection(session: session)
        loading["readiness"] = "loading"; loading["storage"] = "unknown"
        loading["journeyId"] = NSNull(); loading["revision"] = NSNull(); loading["eventCount"] = NSNull()
        XCTAssertEqual(try HostedPlayProjection.decode(loading, sessionID: session, after: 0).readiness, .loading)
        loading["eventCount"] = 1
        XCTAssertThrowsError(try HostedPlayProjection.decode(loading, sessionID: session, after: 0))
        var huge = projection(session: session); huge["revision"] = String(repeating: "x", count: 4097)
        XCTAssertThrowsError(try HostedPlayProjection.decode(huge, sessionID: session, after: 0))
        huge = projection(session: session); huge["visible"] = 1
        XCTAssertThrowsError(try HostedPlayProjection.decode(huge, sessionID: session, after: 0))
    }

    func testDelayedDownloadPreservesNewOrEditedDestinationBytes() throws {
        let directory = try assetsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json"), destination = directory.appendingPathComponent("chosen.json")
        try Data("{\"copy\":1}".utf8).write(to: source)
        let absent = try HostedPlayTransfer.captureDestination(destination)
        let external = Data("{\"external\":2}".utf8)
        try external.write(to: destination)
        XCTAssertThrowsError(try HostedPlayTransfer.finish(source: source, destination: destination, approved: absent))
        XCTAssertEqual(try Data(contentsOf: destination), external)
        let approved = try HostedPlayTransfer.captureDestination(destination)
        let edited = Data("{\"external\":3}".utf8)
        try edited.write(to: destination, options: .atomic)
        XCTAssertThrowsError(try HostedPlayTransfer.finish(source: source, destination: destination, approved: approved))
        XCTAssertEqual(try Data(contentsOf: destination), edited)
    }

    func testDownloadReadbackSucceedsForApprovedAbsentAndUnchangedExistingFiles() throws {
        let directory = try assetsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.json"), destination = directory.appendingPathComponent("chosen.json")
        let bytes = Data("{\"copy\":1}".utf8)
        try bytes.write(to: source)
        let first = try HostedPlayTransfer.finish(source: source, destination: destination, approved: HostedPlayTransfer.captureDestination(destination))
        XCTAssertEqual(first.byteCount, bytes.count)
        XCTAssertEqual(first.sha256.count, 64)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        let second = try HostedPlayTransfer.finish(source: source, destination: destination, approved: HostedPlayTransfer.captureDestination(destination))
        XCTAssertEqual(second, first)
    }

    @MainActor
    func testManagedServerRejectsOccupiedPortAndReleasesItsListenerOnShutdown() async throws {
        let directory = try assetsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try HostedPlayAssets(directory: directory)
        let port = UInt16.random(in: 49_000...59_000)
        let first = HostedPlayAssetServer(assets: assets, port: port)
        let second = HostedPlayAssetServer(assets: assets, port: port)
        let origin = try await first.start()
        do {
            _ = try await second.start()
            XCTFail("A second listener must fail rather than attach to the first")
        } catch { XCTAssertTrue(error is HostedPlayError) }
        let (bytes, response) = try await URLSession.shared.data(from: origin)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("/assets/app.js"))
        await second.shutdown(); await first.shutdown()
        let replacement = HostedPlayAssetServer(assets: assets, port: port)
        _ = try await replacement.start()
        await replacement.shutdown()
    }

    private var authority: String { "127.0.0.1:43822" }
    private func request(_ line: String, extra: String = "") -> Data { Data("\(line)\r\nHost: \(authority)\r\n\(extra)\r\n".utf8) }
    private func assetsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-hosted-play-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("<html><script type='module' src='/assets/app.js'></script></html>".utf8).write(to: directory.appendingPathComponent("index.html"))
        try Data("console.log('bundled');".utf8).write(to: directory.appendingPathComponent("assets/app.js"))
        return directory
    }
    private func projection(session: UUID) -> [String: Any] {
        ["version": 1, "host": "archi-desktop", "sessionId": session.uuidString, "sequence": 1,
         "kind": "journey-projection", "readiness": "ready", "storage": "local-browser", "mode": "habitat",
         "journeyId": "journey-1", "revision": "journey-1:8:event-8", "eventCount": 8, "visible": true]
    }
}
