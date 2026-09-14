import AppKit
import SwiftUI
import XCTest
@testable import ARCHiDesktop

final class KinEvolutionWorkspaceTests: XCTestCase {
    /// Hidden native rendering is a visual fixture, not click or VoiceOver proof.
    /// The existing evolution owner still performs withdrawal and explicit saves.
    @MainActor
    func testKinRecordsRenderAndWithdrawWithoutChangingIdentityLessonsOrPlacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kin-development-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferenceURL = directory.appendingPathComponent("preferences.json")
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let origin = String(repeating: "a", count: 64)
        let lesson = KeptLesson(revision: 2, topic: "Planning a writing session",
            text: "Begin with a short outline and one next step.", createdAt: now)
        let kin = LocalQiMon(character: .kin, originDigest: origin, welcomedAt: now)
        let preferenceBytes = try NativePreferenceDocument(lessons: [lesson], qiMon: kin).encoded()
        try preferenceBytes.write(to: preferenceURL)
        let client = KinDevelopmentNoCalls()
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: false)
        store.preferences.reduceMotion = true
        store.section = .evolution
        store.placed(at: CGPoint(x: 500, y: 350))
        store.evolution.confirmRole(.muse)
        store.evolution.confirmHelpStyle(.reflective)
        let current = LessonSnapshot(lesson: lesson)
        let historical = LessonSnapshot(id: lesson.id, revision: 1, topic: lesson.topic,
            text: "An earlier outline preference.")
        let currentID = UUID(), historicalID = UUID(), plainID = UUID()
        let records: [(UUID, LessonSnapshot?)] = [(currentID, current), (historicalID, historical), (plainID, nil)]
        for (id, snapshot) in records {
            var receipt = AssistantLaneReceipt(requestID: id.uuidString, route: .local, provider: .qwen,
                context: store.contextTicket(), inputDigest: String(repeating: "b", count: 64),
                sourceDigest: origin, inputContract: "native-assistant-input/v4", deadline: .distantFuture,
                modelIdentity: "synthetic-fixture", state: .complete)
            if let snapshot {
                receipt.localLessons = [snapshot]
                receipt.usedLessonIDs = [snapshot.modelID]
            }
            XCTAssertTrue(store.evolution.markUseful(receipt: receipt, sourceDigest: origin, confirmedLesson: snapshot))
        }
        XCTAssertTrue(store.hasPersonalQiMon)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertEqual(store.evolution.usefulReceipts.count, 3)
        XCTAssertEqual(store.evolution.usefulReceipts.compactMap(\.lessonUse).count, 2)
        XCTAssertTrue(store.lessonUseDescription(try XCTUnwrap(store.evolution.usefulReceipts[0].lessonUse)).contains(lesson.topic))
        XCTAssertTrue(store.lessonUseDescription(try XCTUnwrap(store.evolution.usefulReceipts[1].lessonUse)).contains("no longer kept"))
        let position = store.position, placement = store.placementRevision
        let preferences = store.preferences, guidance = store.evolution.preferences
        let identity = store.activeQiMon, appearance = store.reactor.appearanceID

        try await render(store, expanded: false, name: "kin-development-summary")
        try await render(store, expanded: true, name: "kin-development-records")
        XCTAssertTrue(store.evolution.save(), store.evolution.status)
        let saved = try Data(contentsOf: directory.appendingPathComponent("preferences.evolution.json"))
        store.evolution.withdrawLessonUse(requestID: currentID)
        XCTAssertEqual(store.evolution.usefulReceipts.count, 3)
        XCTAssertEqual(store.evolution.usefulReceipts.compactMap(\.lessonUse).count, 1)
        store.evolution.withdrawUseful(requestID: historicalID)
        XCTAssertEqual(store.evolution.usefulReceipts.count, 2)
        XCTAssertTrue(store.evolution.usefulReceipts.allSatisfy { $0.lessonUse == nil })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("preferences.evolution.json")), saved,
            "Inspecting and withdrawing records must not bypass explicit Save evolution")
        try await render(store, expanded: true, name: "kin-development-withdrawn")
        XCTAssertTrue(store.evolution.save(), store.evolution.status)
        let reloaded = CompanionStore(preferenceURL: preferenceURL, assistant: client,
            assistantFactory: { _, _ in client }, wallClock: { now }, allowsPlay: false)
        XCTAssertTrue(reloaded.evolution.usefulReceipts.isEmpty, "Development records still require explicit Load")
        XCTAssertTrue(reloaded.evolution.load(), reloaded.evolution.status)
        XCTAssertEqual(reloaded.evolution.usefulReceipts, store.evolution.usefulReceipts)
        XCTAssertEqual(reloaded.keptLessons, [lesson])
        XCTAssertEqual(reloaded.keptQiMon, kin)
        XCTAssertEqual(store.activeQiMon, identity)
        XCTAssertEqual(store.presentationForm, .kinSeed)
        XCTAssertNil(store.presentationFamily)
        XCTAssertNil(store.presentationRecipe)
        XCTAssertEqual(store.reactor.appearanceID, appearance)
        XCTAssertEqual(store.position, position)
        XCTAssertEqual(store.placementRevision, placement)
        XCTAssertEqual(store.preferences, preferences)
        XCTAssertEqual(store.evolution.preferences, guidance)
        XCTAssertEqual(store.keptLessons, [lesson])
        XCTAssertEqual(try Data(contentsOf: preferenceURL), preferenceBytes)
        XCTAssertEqual(client.calls, 0)
        await reloaded.shutdownAssistant()
        await store.shutdownAssistant()
    }

    @MainActor
    private func render(_ store: CompanionStore, expanded: Bool, name: String) async throws {
        // 880-point minimum workspace less its 220-point sidebar and 64-point padding.
        let width: CGFloat = 596
        let view = EvolutionWorkspace(store: store, evolution: store.evolution,
            lifeRecordsExpanded: expanded, usefulnessRecordsExpanded: expanded)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: width, height: 2400),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.contentView = nil; panel.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        let height = hosting.fittingSize.height
        XCTAssertGreaterThan(height, 100)
        XCTAssertLessThan(height, 2400)
        panel.setContentSize(CGSize(width: width, height: height))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.bounds.width, width, accuracy: 1)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        if let path = ProcessInfo.processInfo.environment["ARCHI_KIN_DEVELOPMENT_RENDER_DIR"] {
            let target = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: target.appendingPathComponent(name + ".png"))
            let evidence: [String: Any] = ["width": width, "height": height, "recordsExpanded": expanded,
                "usefulRequests": store.evolution.usefulReceipts.count,
                "lessonReferences": store.evolution.usefulReceipts.compactMap(\.lessonUse).count,
                "windowShown": false, "realModelCalls": 0,
                "boundary": "Hidden render; native click and VoiceOver acceptance remain separate."]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: target.appendingPathComponent(name + ".json"))
        }
    }
}

@MainActor
private final class KinDevelopmentNoCalls: AssistantClient {
    private(set) var calls = 0
    func connect() async throws { calls += 1; throw AssistantFailure.configuration }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        calls += 1
        throw AssistantFailure.configuration
    }
    func disconnect() {}
}
