import Foundation
import Testing
@testable import ARCHiDesktop

@MainActor
private final class FakeReactorWorker: ReactorWorkerPort {
    var sent: [[String: Any]] = []
    var terminated = false
    var line: (@MainActor @Sendable (Data) -> Void)?
    var exit: (@MainActor @Sendable () -> Void)?
    func launch(onLine: @escaping @MainActor @Sendable (Data) -> Void,
                onExit: @escaping @MainActor @Sendable () -> Void) throws { line = onLine; exit = onExit }
    func send(_ message: Data) { sent.append(try! JSONSerialization.jsonObject(with: message) as! [String: Any]) }
    func terminate() { terminated = true }
    var id: String { sent.first?["requestId"] as? String ?? "" }
    func emit(_ values: [String: Any], requestID: String? = nil) {
        var event = values; event["requestId"] = requestID ?? id
        line?(try! JSONSerialization.data(withJSONObject: event))
    }
    func ready() { emit(["event": "preflight", "runtimeReady": true, "rateCreditsPerSecond": 17, "creditsPerUSD": 10000]) }
}

@Suite @MainActor
struct ReactorExpressionStoreTests {
    private func fixture() throws -> Data { try Data(contentsOf: #require(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.lumenFilename))) }
    private func store(_ workers: [FakeReactorWorker], clock: @escaping () -> Date = Date.init) throws -> ReactorExpressionStore {
        var index = 0
        let store = ReactorExpressionStore(now: clock, factory: {
            guard index < workers.count else { throw CocoaError(.executableLoad) }
            defer { index += 1 }; return workers[index]
        })
        store.updateReference(id: "lumen-reference", label: "Lumen Pearl", png: try fixture(), motionAllowed: true, visible: true)
        return store
    }
    private func prepare(_ store: ReactorExpressionStore, _ worker: FakeReactorWorker) throws -> ReactorTrialQuote {
        store.prepare(); worker.ready(); return try #require(store.quote)
    }

    @Test func checkOnlyRequestsPublicPreflightAndCapturesReferenceQuote() throws {
        let worker = FakeReactorWorker(), subject = try store([worker])
        subject.prepare()
        #expect(worker.sent.count == 1)
        #expect(worker.sent[0]["command"] as? String == "preflight")
        #expect(worker.sent[0]["apiKey"] == nil)
        worker.ready()
        #expect(subject.state == .prepared); #expect(subject.canStart)
        #expect(subject.quote?.maximumCredits == 255)
        #expect(worker.terminated)
    }

    @Test func startUsesFreshWorkerAndExactReviewedBudgetWithNoConcurrentStart() throws {
        let check = FakeReactorWorker(), live = FakeReactorWorker(), subject = try store([check, live])
        let quote = try prepare(subject, check)
        subject.updateCue(.working)
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: quote)
        #expect(subject.state == .connecting)
        #expect(live.sent.count == 1)
        #expect(live.sent[0]["durationSeconds"] as? Int == 15)
        #expect(live.sent[0]["maximumCredits"] as? Double == 255)
        #expect(abs((live.sent[0]["maximumUSD"] as? Double ?? 0) - 0.0255) < 0.000000000001)
        #expect(live.sent[0]["cue"] as? String == "working")
        #expect(live.sent[0]["model"] as? String == "reactor/helios")
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: quote)
        #expect(live.sent.count == 1)
        subject.stop(); live.emit(["event": "closed", "terminationConfirmed": true])
    }

    @Test func changedReferenceAndExpiredQuotesCannotStart() throws {
        var date = Date(timeIntervalSince1970: 1000)
        let check = FakeReactorWorker(), subject = try store([check], clock: { date })
        let quote = try prepare(subject, check)
        date.addTimeInterval(301)
        #expect(!subject.canStart)
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: quote)
        #expect(check.sent.count == 1)
        subject.updateReference(id: "different", label: "Pearl", png: try fixture(), motionAllowed: true, visible: true)
        #expect(subject.quote == nil)
    }

    @Test func stoppedRequestCannotPublishLateOrInFlightFrames() async throws {
        let check = FakeReactorWorker(), live = FakeReactorWorker(), subject = try store([check, live])
        let quote = try prepare(subject, check)
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: quote)
        let reference = try fixture()
        let candidate = try ReactorFrameCompositor.makeProviderReference(approvedReferencePNG: reference)
        live.emit(["event": "frame", "sequence": 1, "png": candidate.base64EncodedString()])
        subject.stop()
        live.emit(["event": "frame", "sequence": 2, "png": candidate.base64EncodedString()])
        try await Task.sleep(for: .milliseconds(600))
        #expect(subject.framePNG == nil); #expect(subject.state == .stopping)
        live.emit(["event": "closed", "terminationConfirmed": true])
        live.emit(["event": "frame", "sequence": 3, "png": candidate.base64EncodedString()])
        #expect(subject.state == .stopped); #expect(subject.terminationConfirmed == true)
        #expect(subject.framePNG == nil)
    }

    @Test func quietModeStopsTheOwnedTrialAndCannotPreview() throws {
        let check = FakeReactorWorker(), live = FakeReactorWorker(), subject = try store([check, live])
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: try prepare(subject, check))
        subject.updateReference(id: "lumen-reference", label: "Lumen Pearl", png: try fixture(), motionAllowed: false, visible: true)
        #expect(subject.state == .stopping); #expect(!subject.canPreview)
        #expect(live.sent.last?["command"] as? String == "stop")
        live.emit(["event": "closed", "terminationConfirmed": false])
        #expect(subject.state == .failed); #expect(subject.terminationConfirmed == false)
    }

    @Test func confirmedClosureDoesNotRelabelFailedTrialAsSuccess() throws {
        let check = FakeReactorWorker(), live = FakeReactorWorker(), subject = try store([check, live])
        subject.startLive(apiKey: "rk_fixture_only_123456", reviewedQuote: try prepare(subject, check))
        live.emit(["event": "closed", "terminationConfirmed": true, "reason": "failed"])
        #expect(subject.state == .failed)
        #expect(subject.terminationConfirmed == true)
        #expect(subject.framePNG == nil)
    }

    @Test func staleCheckAndWrongOwnerCannotRelabelAReplacement() throws {
        let old = FakeReactorWorker(), new = FakeReactorWorker(), subject = try store([old, new])
        subject.prepare(); subject.stop(); subject.prepare()
        old.ready(); new.emit(["event": "closed", "terminationConfirmed": true], requestID: old.id)
        #expect(subject.state == .checking); #expect(subject.quote == nil)
        new.ready(); #expect(subject.state == .prepared)
    }

    @Test func localPreviewDoesNotLaunchProviderAndLateWorkCannotReviveIt() async throws {
        let subject = try store([])
        subject.startLocalPreview()
        for _ in 0..<30 where subject.acceptedFrames == 0 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(subject.acceptedFrames > 0); #expect(subject.state == .previewing)
        subject.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(subject.framePNG == nil); #expect(subject.state == .stopped)
        #expect(subject.terminationConfirmed == nil)
    }

    @Test func MCPDoesNotAcceptLiveStartOrExposeSecrets() throws {
        let subject = try store([])
        #expect(subject.control(["action": "start", "apiKey": "rk_fixture_only_123456"])["ok"] as? Bool == false)
        let result = subject.control(["action": "status"])
        #expect(result["apiKey"] == nil); #expect(result["referencePNG"] == nil)
    }
}
