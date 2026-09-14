import AppKit
import WebKit
import XCTest
@testable import ARCHiDesktop

final class TealFamilyHostTests: XCTestCase {
    /// Exercises the existing native renderer, transport, image decoder and
    /// floating AppKit boundary against an isolated acceptance Journey.
    @MainActor
    func testTealFormsAndEquipmentRetainTheNativeIndividualAndRejectALateImage() async throws {
        guard let assets = ProcessInfo.processInfo.environment["ARCHI_HOSTED_ASSETS_DIR"] else {
            throw XCTSkip("Provide bundled native assets to verify the teal family in the retained Habitat host.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archi-teal-host-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assistant = TealHostAssistant()
        let preferenceURL = directory.appendingPathComponent("preferences.json")
        let store = CompanionStore(preferenceURL: preferenceURL, assistant: assistant)
        store.chooseStartingForm(.particle)
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        let frame = panel.window.frame, placement = store.placementRevision
        let context = store.contextTicket(), settings = store.nextReplySettings
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        host.onJourneyOriginChanged = { [weak store] origin in store?.evolution.observeJourneyOrigin(origin) }
        host.updateAppearance(form: .particle, family: nil, reduceMotion: true)
        host.start()
        do {
            let deadline = Date().addingTimeInterval(20)
            while host.state != .ready || host.projection?.originDigest == nil {
                guard host.state != .unavailable, Date() < deadline else {
                    throw NSError(domain: "TealNativeHost", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: host.status])
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            let view = try XCTUnwrap(host.webView)
            let session = host.sessionID, origin = try XCTUnwrap(host.projection?.originDigest)
            let natural = try XCTUnwrap(store.evolution.naturalVariation)
            let history = store.evolution.history
            let particleID = CompanionVisualAsset.appearanceID(form: .particle, family: nil, treatment: .original)
            _ = try await waitForAppearance(particleID, view: view, host: host)
            let before = try await continuity(view)
            XCTAssertFalse(host.isVisible)
            XCTAssertNil(view.window, "Appearance delivery must not require another presented window")

            var accepted = Set<String>()
            for form in [CompanionForm.constellation, .sprout, .ribbonSpirit, .geode] {
                for equipment in [CompanionEquipment.empty, CompanionEquipment(hand: .focusStaff)] {
                    store.chooseStartingForm(form)
                    store.preferences.equipment = equipment
                    host.updateAppearance(form: form, family: nil, reduceMotion: true,
                        naturalVariation: natural, equipment: equipment)
                    let id = CompanionVisualAsset.appearanceID(form: form, family: nil,
                        treatment: .original, naturalVariation: natural, equipment: equipment)
                    _ = try await waitForAppearance(id, view: view, host: host)
                    XCTAssertTrue(accepted.insert(id).inserted, "Each body and equipment choice must reach the scene distinctly")
                    let label = try XCTUnwrap(panel.window.contentView?.accessibilityValue() as? String)
                    XCTAssertTrue(label.contains(form.rawValue), "The actual floating control must name the incoming body")
                    XCTAssertEqual(label.contains("Focus Staff"), !equipment.isEmpty)
                    XCTAssertTrue(label.hasSuffix("Assistant: Idle"))
                    XCTAssertEqual(panel.window.frame, frame)
                    XCTAssertEqual(store.placementRevision, placement)
                    XCTAssertEqual(store.contextTicket(), context)
                    XCTAssertEqual(store.nextReplySettings, settings)
                    XCTAssertEqual(store.evolution.naturalVariation, natural)
                    XCTAssertEqual(store.evolution.history, history)
                    XCTAssertEqual(host.sessionID, session)
                    XCTAssertEqual(host.projection?.originDigest, origin)
                    XCTAssertTrue(host.webView === view, "All options must retain the existing Habitat view")
                    let after = try await continuity(view)
                    XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: before),
                        "A drawing or equipment selection must not mutate saved Journey, activity or position")
                }
            }

            // Hold one real decoded image callback. The next image uses the
            // original DOM constructor and production callback normally.
            _ = try await view.callAsyncJavaScript("""
                const original = window.Image;
                const fixture = { original, intercepted: 0, ready: false, release: null };
                window.__tealDecodeFixture = fixture;
                window.Image = function(...args) {
                  const image = new original(...args);
                  if (fixture.intercepted++ === 0) {
                    let callback = null;
                    Object.defineProperty(image, 'onload', {
                      configurable: true, get: () => callback, set: value => { callback = value; }
                    });
                    image.addEventListener('load', event => {
                      fixture.release = () => { if (callback) callback.call(image, event); };
                      fixture.ready = true;
                    }, { once: true });
                  }
                  return image;
                };
                window.Image.prototype = original.prototype;
                return true;
                """, arguments: [:], in: nil, contentWorld: .page)
            host.updateAppearance(form: .geode, family: nil, reduceMotion: true)
            let decodeDeadline = Date().addingTimeInterval(10)
            while try await view.callAsyncJavaScript("return window.__tealDecodeFixture.ready;",
                arguments: [:], in: nil, contentWorld: .page) as? Bool != true {
                guard Date() < decodeDeadline else {
                    throw NSError(domain: "TealNativeHost", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The controlled older teal image never decoded"])
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            store.chooseStartingForm(.particle)
            store.preferences.equipment = .empty
            host.updateAppearance(form: .particle, family: nil, reduceMotion: true)
            _ = try await waitForAppearance(particleID, view: view, host: host)
            _ = try await view.callAsyncJavaScript("""
                const fixture = window.__tealDecodeFixture;
                fixture.release();
                window.Image = fixture.original;
                delete window.__tealDecodeFixture;
                return true;
                """, arguments: [:], in: nil, contentWorld: .page)
            let returned = try await appearance(view)
            XCTAssertEqual(returned["id"] as? String, particleID,
                "A deliberately late decoded teal frame must not revive over the returned Particle light")
            XCTAssertEqual(returned["ready"] as? Bool, true)
            let after = try await continuity(view)
            XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: before))
            XCTAssertEqual(host.sessionID, session)
            XCTAssertEqual(host.projection?.originDigest, origin)
            XCTAssertTrue(host.webView === view)
            XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, "Particle light. Assistant: Idle")
            XCTAssertEqual(panel.window.frame, frame)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(store.evolution.naturalVariation, natural)
            XCTAssertEqual(store.evolution.history, history)
            XCTAssertEqual(assistant.invocations, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: preferenceURL.path),
                "Trying forms does not opt into saved preferences")
            print("Teal family native handoff: four bodies with and without staff; one retained Habitat/session/origin; unchanged Journey bytes; late image rejected; native accessibility and placement preserved.")
            await host.shutdown()
            await store.shutdownAssistant()
        } catch {
            print("Teal family handoff diagnostics: \(host.appearanceDeliveryDiagnostics)")
            await host.shutdown()
            await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor
    func testTealStarterKeepsAndReturnsFromAnExistingFamilyInTheSameNativeHost() async throws {
        guard let assets = ProcessInfo.processInfo.environment["ARCHI_HOSTED_ASSETS_DIR"] else {
            throw XCTSkip("Provide bundled native assets for teal starter and evolved-family handoff.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archi-teal-evolution-host-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assistant = TealHostAssistant()
        let store = CompanionStore(preferenceURL: directory.appendingPathComponent("preferences.json"), assistant: assistant)
        store.chooseStartingForm(.sprout)
        let panel = CompanionPanelController(store: store)
        defer { panel.window.orderOut(nil) }
        let frame = panel.window.frame, placement = store.placementRevision
        let host = HostedPlayHost(profile: .acceptance, assetDirectory: URL(fileURLWithPath: assets))
        host.onJourneyOriginChanged = { [weak store] origin in store?.evolution.observeJourneyOrigin(origin) }
        host.updateAppearance(form: .sprout, family: nil, reduceMotion: true)
        host.start()
        do {
            let deadline = Date().addingTimeInterval(20)
            while host.state != .ready || host.projection?.originDigest == nil {
                guard host.state != .unavailable, Date() < deadline else {
                    throw NSError(domain: "TealNativeHost", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: host.status])
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            let view = try XCTUnwrap(host.webView)
            let session = host.sessionID, origin = try XCTUnwrap(host.projection?.originDigest)
            let natural = try XCTUnwrap(store.evolution.naturalVariation)
            let starterID = CompanionVisualAsset.appearanceID(form: .sprout, family: nil, treatment: .original)
            let starterPNG = try XCTUnwrap(CompanionPresenceArt.png(form: .sprout, family: nil))
            _ = try await waitForAppearance(starterID, view: view, host: host)
            let before = try await continuity(view)

            store.evolution.confirmFamily(.lumen)
            let proposal = try XCTUnwrap(store.evolution.proposeEvolution())
            XCTAssertNil(store.evolution.activeFamily, "Preview must not change the desktop's kept form")
            let stillStarter = try await appearance(view)
            XCTAssertEqual(stillStarter["id"] as? String, starterID)
            XCTAssertTrue(store.evolution.keepEvolution(proposal))
            let family = try XCTUnwrap(store.evolution.activeFamily)
            XCTAssertEqual(family, .lumen)
            host.updateAppearance(form: store.preferences.form, family: family, reduceMotion: true,
                naturalVariation: natural)
            let evolvedID = CompanionVisualAsset.appearanceID(form: .sprout, family: family,
                treatment: .original, naturalVariation: natural)
            let evolvedPNG = try XCTUnwrap(CompanionPresenceArt.png(form: .sprout, family: family,
                naturalVariation: natural))
            XCTAssertNotEqual(evolvedID, starterID)
            XCTAssertNotEqual(evolvedPNG, starterPNG, "The teal starter must not mask the selected evolved body")
            _ = try await waitForAppearance(evolvedID, view: view, host: host)
            let evolvedLabel = try XCTUnwrap(panel.window.contentView?.accessibilityValue() as? String)
            XCTAssertTrue(evolvedLabel.contains(EvolutionFamily.lumen.title))
            XCTAssertFalse(evolvedLabel.contains(CompanionForm.sprout.rawValue))
            XCTAssertEqual(store.evolution.history.map(\.kind), [.kept])

            store.chooseStartingForm(.sprout)
            host.updateAppearance(form: store.preferences.form, family: store.evolution.activeFamily,
                reduceMotion: true, naturalVariation: natural)
            _ = try await waitForAppearance(starterID, view: view, host: host)
            XCTAssertEqual(panel.window.contentView?.accessibilityValue() as? String, "Jade Sprout. Assistant: Idle")
            XCTAssertEqual(store.evolution.history.map(\.kind), [.kept, .returned])
            XCTAssertNil(store.evolution.activeFamily)
            XCTAssertEqual(store.evolution.naturalVariation, natural)
            XCTAssertTrue(store.evolution.usefulReceipts.isEmpty)
            XCTAssertTrue(store.evolution.reviewedPractices.isEmpty)
            XCTAssertEqual(panel.window.frame, frame)
            XCTAssertEqual(store.placementRevision, placement)
            XCTAssertEqual(host.sessionID, session)
            XCTAssertEqual(host.projection?.originDigest, origin)
            XCTAssertTrue(host.webView === view)
            let after = try await continuity(view)
            XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: before),
                "Only the user's explicit appearance Keep/Return history changes; the canonical play Journey does not")
            XCTAssertEqual(assistant.invocations, 0)
            print("Teal evolution handoff: Jade Sprout → explicit Lumen Keep → Jade Sprout; distinct accepted artwork and labels; same origin, placement, view, session and Journey.")
            await host.shutdown()
            await store.shutdownAssistant()
        } catch {
            await host.shutdown()
            await store.shutdownAssistant()
            throw error
        }
    }

    @MainActor
    private func waitForAppearance(_ id: String, view: WKWebView, host: HostedPlayHost) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(15)
        var last: [String: Any] = [:]
        while Date() < deadline {
            last = try await appearance(view)
            if last["id"] as? String == id, last["ready"] as? Bool == true { return last }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "TealNativeHost", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Expected \(id); last image \(last); delivery \(host.appearanceDeliveryDiagnostics)"])
    }

    @MainActor
    private func appearance(_ view: WKWebView) async throws -> [String: Any] {
        let raw = try await view.callAsyncJavaScript("return JSON.parse(window.render_game_to_text()).companion.nativeAppearance;",
            arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(raw as? [String: Any])
    }

    @MainActor
    private func continuity(_ view: WKWebView) async throws -> [String: Any] {
        let raw = try await view.callAsyncJavaScript("""
            const state = JSON.parse(window.render_game_to_text());
            return {
              savedJourney: localStorage.getItem('archi.journey.v3'),
              revision: state.journey.revision, eventCount: state.journey.ledger.eventCount,
              player: {x: state.companion.x, y: state.companion.y, vx: state.companion.vx, vy: state.companion.vy},
              practice: state.battle, activityMilestones: state.activityMilestones
            };
            """, arguments: [:], in: nil, contentWorld: .page)
        return try XCTUnwrap(raw as? [String: Any])
    }
}

@MainActor
private final class TealHostAssistant: AssistantClient {
    private(set) var invocations = 0
    func connect() async throws { invocations += 1 }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        invocations += 1
    }
    func disconnect() {}
}
