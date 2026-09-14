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

    func testVersionThreeWhatIfAndLegacyProjectionsDecodeWithoutChangingLegacyShape() throws {
        let session = UUID()
        let current = try HostedPlayProjection.decode(whatIfProjection(session: session), sessionID: session, after: 0)
        XCTAssertEqual(current.version, 3)
        XCTAssertEqual(current.arena?.whatIf?.firstId, "pulse")
        XCTAssertEqual(current.arena?.whatIf?.cases.first?.second, "Both recover Spark.")
        var legacy = whatIfProjection(session: session)
        legacy["version"] = 2
        var arena = try XCTUnwrap(legacy["arena"] as? [String: Any]); arena.removeValue(forKey: "whatIf")
        legacy["arena"] = arena
        XCTAssertNil(try HostedPlayProjection.decode(legacy, sessionID: session, after: 0).arena?.whatIf)
        XCTAssertEqual(try HostedPlayProjection.decode(projection(session: session), sessionID: session, after: 0).version, 1)
        arena["whatIf"] = NSNull(); legacy["arena"] = arena
        XCTAssertThrowsError(try HostedPlayProjection.decode(legacy, sessionID: session, after: 0), "v2 keeps its historical closed shape")
    }

    func testVersionThreeRequiresNullableWhatIfAndExactNestedKeys() throws {
        let session = UUID(), original = whatIfProjection(session: session)
        var arena = try XCTUnwrap(original["arena"] as? [String: Any]), candidate = original
        arena["whatIf"] = NSNull(); candidate["arena"] = arena
        XCTAssertNil(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0).arena?.whatIf)
        arena.removeValue(forKey: "whatIf"); candidate["arena"] = arena
        XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
        for expanded in ["root", "choice", "case"] {
            var changed = whatIfDictionary()
            switch expanded {
            case "root": changed["hiddenMove"] = "guard"
            case "choice":
                var choices = changed["choices"] as! [[String: Any]]; choices[0]["permission"] = true; changed["choices"] = choices
            default:
                var cases = changed["cases"] as! [[String: Any]]; cases[0]["probability"] = 0.9; changed["cases"] = cases
            }
            arena["whatIf"] = changed; candidate["arena"] = arena
            XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0), expanded)
        }
    }

    func testWhatIfRejectsDuplicateUnknownAndUnboundedChoicesAndCases() throws {
        let session = UUID(), original = whatIfProjection(session: session)
        let good = whatIfDictionary(), choices = good["choices"] as! [[String: Any]], cases = good["cases"] as! [[String: Any]]
        var invalid: [[String: Any]] = []
        for (key, value) in [("firstId", "missing"), ("firstId", "guard"), ("secondId", ""), ("firstId", String(repeating: "x", count: 161))] {
            var changed = good; changed[key] = value; invalid.append(changed)
        }
        for list in [[], [choices[0]], [choices[0], choices[0]], Array(repeating: choices[0], count: 8)] {
            var changed = good; changed["choices"] = list; invalid.append(changed)
        }
        for list in [[], [cases[0], cases[0]], Array(repeating: cases[0], count: 8)] {
            var changed = good; changed["cases"] = list; invalid.append(changed)
        }
        for (key, value) in [("id", ""), ("label", String(repeating: "🦋", count: 31)), ("detail", String(repeating: "x", count: 301))] {
            var changed = good, list = choices; list[0][key] = value; changed["choices"] = list; invalid.append(changed)
        }
        for key in ["opponentId", "opponentLabel", "first", "second"] {
            for value in ["", Double.nan, Double.infinity, true] as [Any] {
                var changed = good, list = cases; list[0][key] = value; changed["cases"] = list; invalid.append(changed)
            }
        }
        for (key, limit) in [("opponentId", 160), ("opponentLabel", 120), ("first", 700), ("second", 700)] {
            var changed = good, list = cases; list[0][key] = String(repeating: "x", count: limit + 1); changed["cases"] = list; invalid.append(changed)
        }
        for changed in invalid {
            var candidate = original, arena = original["arena"] as! [String: Any]
            arena["whatIf"] = changed; candidate["arena"] = arena
            XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
        }
    }

    func testWhatIfOnlyAllowedInActivePlanningAndArenaModes() throws {
        let session = UUID(), original = whatIfProjection(session: session)
        for override in [["phase": "sealed"], ["phase": "finished"], ["phase": "entry", "battleId": NSNull(), "round": 0],
                         ["battleId": NSNull()], ["round": 0], ["round": Double.nan], ["round": Double.infinity]] as [[String: Any]] {
            var candidate = original, arena = original["arena"] as! [String: Any]
            arena.merge(override) { _, new in new }; candidate["arena"] = arena
            XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
        }
        var candidate = original; candidate["mode"] = "field"
        XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
    }

    func testWhatIfMaximumValidBranchShapeAndCombinedPayloadBudget() throws {
        let session = UUID(); var candidate = whatIfProjection(session: session)
        let choices = (0..<7).map { ["id": String($0).padding(toLength: 160, withPad: "x", startingAt: 0),
                                    "label": String(repeating: "l", count: 120), "detail": String(repeating: "d", count: 300)] }
        let cases = (0..<7).map { ["opponentId": String($0).padding(toLength: 160, withPad: "x", startingAt: 0),
                                  "opponentLabel": String(repeating: "l", count: 120), "first": String(repeating: "a", count: 700), "second": String(repeating: "b", count: 700)] }
        var arena = candidate["arena"] as! [String: Any]
        arena["whatIf"] = ["choices": choices, "firstId": choices[0]["id"]!, "secondId": choices[1]["id"]!, "cases": cases]
        candidate["arena"] = arena
        XCTAssertEqual(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0).arena?.whatIf?.cases.count, 7)
        arena["actions"] = (0..<32).map { ["id": String($0).padding(toLength: 160, withPad: "x", startingAt: 0),
                                           "label": String(repeating: "l", count: 120), "detail": String(repeating: "d", count: 300)] }
        candidate["arena"] = arena
        XCTAssertGreaterThan(try JSONSerialization.data(withJSONObject: candidate).count, 32_768)
        XCTAssertThrowsError(try HostedPlayProjection.decode(candidate, sessionID: session, after: 0))
    }

    func testDecodedWhatIfOwnsValuesAndRejectedGateMessageDoesNotAdvance() throws {
        var gate = HostedPlayProjectionGate(); gate.begin()
        let original = whatIfProjection(session: gate.sessionID)
        let changedCase = NSMutableDictionary(dictionary: (whatIfDictionary()["cases"] as! [[String: Any]])[0])
        var candidate = original, whatIf = whatIfDictionary(), arena = original["arena"] as! [String: Any]
        whatIf["cases"] = [changedCase]; arena["whatIf"] = whatIf; candidate["arena"] = arena
        let admitted = try gate.receive(candidate)
        changedCase["first"] = "Mutated after receipt"
        XCTAssertEqual(admitted.arena?.whatIf?.cases.first?.first, "Your Pulse meets their shield.")
        candidate["sequence"] = 2; arena["whatIf"] = ["firstId": "unknown"]; candidate["arena"] = arena
        XCTAssertThrowsError(try gate.receive(candidate)); XCTAssertEqual(gate.sequence, 1)
        var repaired = original; repaired["sequence"] = 2
        XCTAssertEqual(try gate.receive(repaired).sequence, 2)
    }

    private func whatIfDictionary() -> [String: Any] {
        ["choices": [["id": "pulse", "label": "Pulse", "detail": "Use Spark."], ["id": "guard", "label": "Guard", "detail": "Recover Spark."]],
         "firstId": "pulse", "secondId": "guard",
         "cases": [["opponentId": "guard", "opponentLabel": "Guard", "first": "Your Pulse meets their shield.", "second": "Both recover Spark."]]]
    }

    private func whatIfProjection(session: UUID) -> [String: Any] {
        var value = projection(session: session)
        value["version"] = 3; value["originDigest"] = String(repeating: "a", count: 64); value["practices"] = []
        value["mode"] = "battle"
        value["arena"] = ["battleId": UUID().uuidString, "revision": String(repeating: "a", count: 64), "phase": "planning", "round": 1,
                          "summary": "Compare two choices.", "actions": [["id": "what-if:close", "label": "Close comparison", "detail": "Return to moves."]],
                          "whatIf": whatIfDictionary()]
        return value
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
