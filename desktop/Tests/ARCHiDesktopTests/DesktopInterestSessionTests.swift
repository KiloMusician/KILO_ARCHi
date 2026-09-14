import Foundation
import XCTest
@testable import ARCHiDesktop

final class DesktopInterestSessionTests: XCTestCase {
    @MainActor
    func testHoverAndFinishOnlySelectMetadataWithoutReading() {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        // Inactive controls cannot acquire a target or begin content access.
        active.hover(at: CGPoint(x: 10, y: 20)); active.finishAim(); active.read()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.target)
        defer { active.cancel() }
        active.begin()
        active.hover(at: CGPoint(x: CGFloat.nan, y: 0))
        XCTAssertEqual(reader.targetCalls, 0)
        active.hover(at: CGPoint(x: 25, y: 40))
        XCTAssertEqual(active.phase, .aiming)
        XCTAssertEqual(active.target, reader.offeredTarget)
        XCTAssertEqual(reader.targetCalls, 1)
        active.finishAim()
        XCTAssertEqual(active.phase, .targeted)
        XCTAssertNil(active.capture)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testMissingOrChangedTargetCannotFinishOrStartReading() {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        active.begin(); active.finishAim()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.target)
        defer { active.cancel() }
        active.begin(); active.hover(at: .zero)
        reader.current = false
        active.finishAim()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertTrue(reader.requests.isEmpty)

        reader.current = true
        chooseTarget(active)
        reader.current = false
        active.read()
        XCTAssertEqual(active.phase, .idle)
        XCTAssertNil(active.capture)
        XCTAssertTrue(reader.requests.isEmpty)
    }

    @MainActor
    func testExplicitReadOccursOnceAndProducesOnlyAReviewSnapshot() async throws {
        let reader = InterestSessionReader()
        let active = DesktopInterestSession(reader: reader)
        active.read()
        XCTAssertEqual(active.phase, .idle)
        defer { active.cancel(); reader.cancelPending() }
        chooseTarget(active)
        XCTAssertTrue(reader.requests.isEmpty)
        active.read(); active.read(); active.finishAim()
        try await interestSettle { reader.requests.count == 1 }
        XCTAssertEqual(active.phase, .reading)
        XCTAssertNil(active.capture)
        XCTAssertEqual(reader.requests[0], reader.offeredTarget)
        let result = reader.snapshot(text: "A synthetic passage to review.")
        reader.complete(0, with: result)
        try await interestSettle { active.phase == .review }
        XCTAssertEqual(active.capture, result)
        XCTAssertEqual(reader.requests.count, 1)
    }

    @MainActor
    func testCancelRejectsLateSuccessAndLateFailure() async throws {
        for fails in [false, true] {
            let reader = InterestSessionReader()
            let active = DesktopInterestSession(reader: reader)
            defer { active.cancel(); reader.cancelPending() }
            chooseTarget(active); active.read()
            try await interestSettle { reader.requests.count == 1 }
            active.cancel(reason: "Cancelled by user")
            if fails { reader.fail(0) }
            else { reader.complete(0, with: reader.snapshot(text: "Late private text")) }
            try await interestSettle { reader.completed.contains(0) }
            await interestDrain()
            XCTAssertEqual(active.phase, .idle)
            XCTAssertNil(active.capture)
            XCTAssertNil(active.target)
            XCTAssertEqual(active.message, "Cancelled by user")
        }
    }

    @MainActor
    func testOldCompletionCannotReplaceOrFailANewerAcquisition() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        reader.offeredTarget = interestTarget(windowID: 222, title: "Second synthetic window")
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 2 }
        let current = reader.snapshot(text: "Current reviewed text")
        reader.complete(1, with: current)
        try await interestSettle { session.phase == .review }
        reader.complete(0, with: reader.snapshot(text: "Old text", target: reader.requests[0]))
        try await interestSettle { reader.completed.contains(0) }
        await interestDrain()
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(session.capture, current)
        XCTAssertEqual(session.target, current.target)
        XCTAssertEqual(reader.requests.count, 2)
    }

    @MainActor
    func testTargetChangeDuringReadRejectsResultWithOrWithoutRefreshNotification() async throws {
        for refreshes in [false, true] {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.current = false
            if refreshes { session.refreshBoundary() }
            reader.complete(0, with: reader.snapshot(text: "A stale window snapshot"))
            try await interestSettle { reader.completed.contains(0) && session.phase != .reading }
            await interestDrain()
            XCTAssertEqual(session.phase, refreshes ? .idle : .failed)
            XCTAssertNil(session.capture)
            XCTAssertEqual(reader.requests.count, 1)
        }
    }

    @MainActor
    func testReturnedWindowIdentityMustMatchEveryCapturedBoundary() async throws {
        let original = interestTarget()
        let mismatches = [
            interestTarget(windowID: original.windowID + 1),
            interestTarget(processID: original.processID + 1),
            interestTarget(appName: "Other synthetic app"),
            interestTarget(title: "Other synthetic document"),
            interestTarget(frame: original.frame.offsetBy(dx: 1, dy: 0))
        ]
        for mismatch in mismatches {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.complete(0, with: reader.snapshot(text: "Mismatched snapshot", target: mismatch))
            try await interestSettle { session.phase == .failed }
            XCTAssertNil(session.capture)
        }
    }

    @MainActor
    func testEmptyWhitespaceAndOversizedUTF8AreRejectedWithoutTruncation() async throws {
        for text in ["", " \n\t ", String(repeating: "a", count: 60_001), String(repeating: "é", count: 30_001)] {
            let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
            defer { session.cancel(); reader.cancelPending() }
            chooseTarget(session); session.read()
            try await interestSettle { reader.requests.count == 1 }
            reader.complete(0, with: reader.snapshot(text: text))
            try await interestSettle { session.phase == .failed }
            XCTAssertNil(session.capture)
            XCTAssertEqual(reader.requests.count, 1)
        }
    }

    @MainActor
    func testExactByteLimitAndStableIdentityWithNewObservationTimeAreAccepted() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        let text = String(repeating: "é", count: 30_000)
        let newerObservation = interestTarget(observedAt: Date(timeIntervalSince1970: 1_800_000_100))
        reader.complete(0, with: reader.snapshot(text: text, target: newerObservation))
        try await interestSettle { session.phase == .review }
        XCTAssertEqual(session.capture?.text, text)
        XCTAssertEqual(session.capture?.text.utf8.count, 60_000)
    }

    @MainActor
    func testReaderFailureKeepsNoCaptureAndCannotPassivelyRetry() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        reader.fail(0)
        try await interestSettle { session.phase == .failed }
        XCTAssertNil(session.capture)
        session.read(); session.hover(at: .zero); session.finishAim(); session.refreshBoundary()
        await interestDrain()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(reader.requests.count, 1)
    }

    @MainActor
    func testProductionReadDeadlineFailsAndRejectsLateSuccess() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session)
        let clock = ContinuousClock()
        let started = clock.now
        let limit = started.advanced(by: .seconds(12))
        session.read()
        try await interestSettle { reader.requests.count == 1 }
        // Exercise the production ten-second deadline. The synthetic reader
        // deliberately stays suspended even when its task is cancelled.
        while session.phase == .reading && clock.now < limit {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard session.phase == .failed else {
            XCTFail("The production read deadline did not fail within twelve seconds")
            throw InterestSessionFailure.timeout
        }
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .seconds(10))
        XCTAssertNil(session.capture)
        XCTAssertTrue(session.message.contains("took too long"))
        let failureMessage = session.message
        reader.complete(0, with: reader.snapshot(text: "Late success must never become a review"))
        try await interestSettle { reader.completed.contains(0) }
        await interestDrain()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(session.capture)
        XCTAssertEqual(session.message, failureMessage)
        session.read()
        await interestDrain()
        XCTAssertEqual(reader.requests.count, 1, "Timeout does not automatically retry")
    }

    @MainActor
    func testReviewStaysCapturedSnapshotWithoutFollowingWindowOrRecapturing() async throws {
        let reader = InterestSessionReader(), session = DesktopInterestSession(reader: reader)
        defer { session.cancel(); reader.cancelPending() }
        chooseTarget(session); session.read()
        try await interestSettle { reader.requests.count == 1 }
        let captured = reader.snapshot(text: "Text as captured at the explicit read")
        reader.complete(0, with: captured)
        try await interestSettle { session.phase == .review }
        let observedCalls = reader.targetCalls, boundaryChecks = reader.currentChecks
        reader.current = false
        reader.offeredTarget = interestTarget(windowID: 333, title: "A different window now")
        session.refreshBoundary(); session.hover(at: CGPoint(x: 99, y: 99)); session.finishAim(); session.read()
        await interestDrain()
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(session.capture, captured)
        XCTAssertEqual(reader.targetCalls, observedCalls)
        XCTAssertEqual(reader.currentChecks, boundaryChecks)
        XCTAssertEqual(reader.requests.count, 1)
        session.cancel()
        XCTAssertNil(session.capture)
        XCTAssertNil(session.target)
    }
}

@MainActor
private func chooseTarget(_ session: DesktopInterestSession) {
    session.begin(); session.hover(at: CGPoint(x: 25, y: 40)); session.finishAim()
    XCTAssertEqual(session.phase, .targeted)
}

private func interestTarget(windowID: UInt32 = 111, processID: Int32 = 4242,
                            appName: String = "Synthetic Editor", title: String = "Synthetic notes",
                            frame: CGRect = CGRect(x: -500, y: 30, width: 400, height: 300),
                            observedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> DesktopInterestTarget {
    DesktopInterestTarget(windowID: windowID, processID: processID, appName: appName, title: title,
                          frame: frame, observedAt: observedAt)
}

@MainActor
private func interestSettle(_ predicate: () -> Bool) async throws {
    for _ in 0..<500 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("Synthetic interest session did not reach its expected state")
    throw InterestSessionFailure.timeout
}

@MainActor
private func interestDrain() async {
    for _ in 0..<20 { await Task.yield() }
}

private enum InterestSessionFailure: Error { case timeout, syntheticReadFailure }

/// Deliberately ignores cancellation until resumed, exercising session ownership
/// fences instead of letting a cooperative platform adapter hide late callbacks.
@MainActor
private final class InterestSessionReader: DesktopInterestReading {
    var offeredTarget = interestTarget()
    var current = true
    var targetCalls = 0, currentChecks = 0
    private(set) var requests: [DesktopInterestTarget] = []
    private(set) var completed: Set<Int> = []
    private var pending: [Int: CheckedContinuation<DesktopInterestCapture, any Error>] = [:]

    func target(at point: CGPoint) -> DesktopInterestTarget? {
        targetCalls += 1
        return offeredTarget
    }

    func isCurrent(_ target: DesktopInterestTarget) -> Bool {
        currentChecks += 1
        return current
    }

    func read(_ target: DesktopInterestTarget) async throws -> DesktopInterestCapture {
        let index = requests.count
        requests.append(target)
        defer { completed.insert(index) }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func snapshot(text: String, target: DesktopInterestTarget? = nil) -> DesktopInterestCapture {
        DesktopInterestCapture(target: target ?? offeredTarget, text: text, method: "Synthetic app-provided text",
                               capturedAt: Date(timeIntervalSince1970: 1_800_000_010))
    }

    func complete(_ index: Int, with result: DesktopInterestCapture) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Missing synthetic read"); return }
        continuation.resume(returning: result)
    }

    func fail(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else { XCTFail("Missing synthetic read"); return }
        continuation.resume(throwing: InterestSessionFailure.syntheticReadFailure)
    }

    func cancelPending() {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
