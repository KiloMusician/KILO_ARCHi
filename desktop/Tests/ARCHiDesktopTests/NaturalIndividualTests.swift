import Foundation
import XCTest
@testable import ARCHiDesktop

final class NaturalIndividualTests: XCTestCase {
    func testFixedOriginReproducesItsNaturalTraits() throws {
        let origin = String(repeating: "0123456789abcdef", count: 4)
        let first = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: origin))
        let again = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: origin))
        XCTAssertEqual(first, again)
        XCTAssertEqual(first.fingerprint, "10df68a686e5824d4a1f86b4c122f0dd898f5f7cb2039d3d923f78dc2550d709")
        XCTAssertEqual(first.horizontalScale, 0.9739542229343099, accuracy: 1e-12)
        XCTAssertEqual(first.hueDegrees, -0.729686427100023, accuracy: 1e-12)
        XCTAssertEqual(first.markingCount, 3)
        XCTAssertEqual(first.markingRotation, 0.8965285725185016 * 2 * .pi, accuracy: 1e-12)
    }

    func testOnlyAValidExistingOriginCanCreateNaturalVariation() {
        for invalid in ["", "not-an-origin", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                        String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                        String(repeating: "é", count: 32)] {
            XCTAssertNil(CompanionNaturalVariation.make(originDigest: invalid))
        }
        XCTAssertNotNil(CompanionNaturalVariation.make(originDigest: String(repeating: "0", count: 64)))
        XCTAssertNotNil(CompanionNaturalVariation.make(originDigest: String(repeating: "f", count: 64)))
    }

    func testSmallNaturalDifferencesRemainBoundedAcrossSampleOrigins() throws {
        var fingerprints = Set<String>()
        for index in 0..<256 {
            let value = try XCTUnwrap(CompanionNaturalVariation.make(originDigest: String(format: "%064x", index)))
            XCTAssertTrue(value.horizontalScale.isFinite && (0.97...1.03).contains(value.horizontalScale))
            XCTAssertTrue(value.hueDegrees.isFinite && (-4...4).contains(value.hueDegrees))
            XCTAssertTrue((1...3).contains(value.markingCount))
            XCTAssertTrue(value.markingRotation.isFinite && (0...(2 * Double.pi)).contains(value.markingRotation))
            XCTAssertEqual(value.fingerprint.utf8.count, 64)
            XCTAssertTrue(value.fingerprint.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
            fingerprints.insert(value.fingerprint)
        }
        XCTAssertEqual(fingerprints.count, 256, "This fixed sample differs; it does not prove universally exclusive artwork")
    }

    @MainActor
    func testObservedIndividualTakesPrecedenceOverHistoricalBinding() throws {
        let originA = String(repeating: "a", count: 64), originB = String(repeating: "b", count: 64)
        let store = EvolutionStore()
        XCTAssertNil(store.naturalVariation)
        XCTAssertTrue(store.bindPracticeJourney(originA))
        let fallback = try XCTUnwrap(store.naturalVariation)
        XCTAssertEqual(fallback.originDigest, originA)
        store.observeJourneyOrigin(originB)
        let actual = try XCTUnwrap(store.naturalVariation)
        XCTAssertEqual(actual.originDigest, originB)
        XCTAssertNotEqual(actual.fingerprint, fallback.fingerprint)
        XCTAssertTrue(store.bindPracticeJourney(originA))
        XCTAssertEqual(store.naturalVariation, actual)
        store.confirmRole(.guardian)
        store.confirmHelpStyle(.reflective)
        store.confirmFamily(.fen)
        XCTAssertTrue(store.keepEvolution(try XCTUnwrap(store.proposeEvolution())))
        XCTAssertEqual(store.naturalVariation, actual)
        XCTAssertTrue(store.forget())
        XCTAssertEqual(store.naturalVariation, actual, "Evolution cannot clear the independent host's current individual")
        XCTAssertNil(store.practiceJourneyOriginDigest)
    }

    @MainActor
    func testUsefulWorkAndReviewedPracticeCannotChangeInheritedDetails() throws {
        let origin = String(repeating: "a", count: 64)
        let store = EvolutionStore()
        store.observeJourneyOrigin(origin)
        XCTAssertTrue(store.bindPracticeJourney(origin))
        let natural = try XCTUnwrap(store.naturalVariation)
        for _ in 0..<3 {
            let receipt = AssistantLaneReceipt(requestID: UUID().uuidString, route: .local, provider: .qwen,
                context: ContextTicket(generation: 1, placement: 2, source: 3, selection: 4),
                inputDigest: origin, sourceDigest: origin, inputContract: AssistantRequest.inputContract,
                deadline: .distantFuture, modelIdentity: nil, state: .complete)
            XCTAssertTrue(store.markUseful(receipt: receipt, sourceDigest: origin))
            XCTAssertEqual(store.naturalVariation, natural)
        }
        let practice = PracticeEvolutionReference(originDigest: origin, eventId: "practice:1", battleId: UUID(),
            rulesVersion: 1, rounds: 5, outcome: .lost, replayDigest: String(repeating: "c", count: 64),
            committedAt: "2026-09-06T18:00:00Z")
        XCTAssertTrue(store.reviewPractice(practice, currentOriginDigest: origin))
        XCTAssertEqual(store.naturalVariation, natural)
        store.withdrawPractice(id: practice.id)
        for id in store.usefulReceipts.map(\.requestID) { store.withdrawUseful(requestID: id) }
        XCTAssertEqual(store.naturalVariation, natural)
        XCTAssertTrue(store.usefulReceipts.isEmpty)
        XCTAssertTrue(store.reviewedPractices.isEmpty)
        XCTAssertEqual(store.preferences.confirmedCount, 0)
        XCTAssertTrue(store.history.isEmpty)
    }

    func testNewAppearanceChoiceCannotMasqueradeAsAHistoricalRecipe() throws {
        let origin = String(repeating: "a", count: 64)
        XCTAssertNil(CompanionAppearanceRecipe.make(originDigest: origin, family: .lumen,
            role: .muse, helpStyle: .exploratory, basisKind: .appearanceChoice))
        var object = try EvolutionLegacyTestData.object()
        var recipe = try XCTUnwrap(object["keptAppearanceRecipe"] as? [String: Any])
        recipe["basisKind"] = EvolutionProposalBasis.Kind.appearanceChoice.rawValue
        object["keptAppearanceRecipe"] = recipe
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionAppearanceRecipe.self,
            from: JSONSerialization.data(withJSONObject: recipe)))
    }
}
