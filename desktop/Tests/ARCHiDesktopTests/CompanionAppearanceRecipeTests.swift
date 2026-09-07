import Foundation
import XCTest
@testable import ARCHiDesktop

final class CompanionAppearanceRecipeTests: XCTestCase {
    private let origin = String(repeating: "0123456789abcdef", count: 4)

    func testFixedVectorAndRoundTripKeepTheExactRecipe() throws {
        let first = try recipe(), repeated = try recipe()
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.fingerprint, "03150414f2f553795ee20094a9f4e6c6141a4a75c066cf98b1c5b48bc5815c63")
        XCTAssertEqual(first.accentHue, 0.4541466392004272, accuracy: 1e-12)
        XCTAssertEqual(first.horizontalScale, 1.0364721141374837, accuracy: 1e-12)
        XCTAssertEqual(first.markingCount, 4)
        XCTAssertEqual(first.markingRotation, 0.7024078369140625 * 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(first.motionSpeed, 1.15)
        XCTAssertEqual(first.roleSymbol, "sparkles")
        let decoded = try JSONDecoder().decode(CompanionAppearanceRecipe.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded, first)
        XCTAssertEqual(decoded.fingerprint, first.fingerprint)
        XCTAssertEqual(decoded.traitExplanations, first.traitExplanations)
    }

    func testDistinctOriginsProduceDistinctRecipesWithoutClaimingExclusiveArtwork() throws {
        let first = try recipe(), other = try recipe(origin: String(repeating: "b", count: 64))
        XCTAssertNotEqual(first.fingerprint, other.fingerprint)
        XCTAssertNotEqual(first.accentHue, other.accentHue)
        XCTAssertNotEqual(first.horizontalScale, other.horizontalScale)
        XCTAssertTrue(first.traitExplanations.contains { $0.reason.contains("do not measure personality or guarantee exclusive artwork") })
    }

    func testEachConfirmedChoiceAffectsItsVisibleTraitAndFingerprint() throws {
        let first = try recipe()
        let roles = try EvolutionRole.allCases.map { try recipe(role: $0) }
        XCTAssertEqual(Set(roles.map(\.accentHue)).count, EvolutionRole.allCases.count)
        XCTAssertEqual(Set(roles.map(\.roleSymbol)).count, EvolutionRole.allCases.count)
        XCTAssertEqual(Set(roles.map(\.fingerprint)).count, EvolutionRole.allCases.count)
        let styles = try EvolutionHelpStyle.allCases.map { try recipe(helpStyle: $0) }
        XCTAssertEqual(Set(styles.map(\.motionSpeed)).count, EvolutionHelpStyle.allCases.count)
        XCTAssertEqual(Set(styles.map(\.fingerprint)).count, EvolutionHelpStyle.allCases.count)
        let family = try recipe(family: .fen)
        XCTAssertNotEqual(first.fingerprint, family.fingerprint)
        XCTAssertNotEqual(first.accentHue, family.accentHue)
        XCTAssertNotEqual(first.horizontalScale, family.horizontalScale)
        let basis = try recipe(basis: .completedPractice)
        XCTAssertNotEqual(first.fingerprint, basis.fingerprint)
        XCTAssertEqual(first.accentHue, basis.accentHue, "Eligibility basis does not grant a stronger appearance")
        XCTAssertEqual(first.horizontalScale, basis.horizontalScale)
        XCTAssertEqual(first.markingCount, basis.markingCount)
        XCTAssertEqual(first.motionSpeed, basis.motionSpeed)
    }

    func testInvalidOriginsCannotBeCreatedOrDecoded() throws {
        let invalid = ["", "a", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                       origin.uppercased(), String(repeating: "g", count: 64),
                       String(repeating: "a", count: 63) + "\n", String(repeating: "é", count: 32)]
        for digest in invalid {
            XCTAssertNil(CompanionAppearanceRecipe.make(originDigest: digest, family: .lumen, role: .muse,
                helpStyle: .exploratory, basisKind: .usefulWork))
            var object = try encodedObject()
            object["originDigest"] = digest
            XCTAssertThrowsError(try decode(object), "Rejected invalid origin: \(digest)")
        }
    }

    func testDecodingRejectsUnsupportedKeysVersionsTypesAndChoices() throws {
        let mutations: [(String, Any)] = [
            ("version", 0), ("version", 2), ("version", "1"), ("version", true),
            ("version", NSNull()), ("family", "unknown"), ("role", "unknown"),
            ("helpStyle", "unknown"), ("basisKind", "unknown"),
            ("unexpected", "value"), ("originDigest", NSNull())
        ]
        for (key, value) in mutations {
            var object = try encodedObject()
            object[key] = value
            XCTAssertThrowsError(try decode(object), "Rejected \(key): \(value)")
        }
        for key in try encodedObject().keys {
            var object = try encodedObject()
            object.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(object), "Missing required key: \(key)")
        }
    }

    func testOnlySavedInputsAreEncodedAndUnrelatedRuntimeContextCannotEnterTheRecipe() throws {
        let first = try recipe(), sameSavedChoices = try recipe()
        let object = try encodedObject()
        XCTAssertEqual(Set(object.keys), ["version", "originDigest", "family", "role", "helpStyle", "basisKind"])
        for forbidden in ["document", "requestID", "deviceID", "timestamp", "quiet", "reduceMotion"] {
            var withRuntimeContext = object
            withRuntimeContext[forbidden] = "unrelated context"
            XCTAssertThrowsError(try decode(withRuntimeContext))
        }
        XCTAssertEqual(first.fingerprint, sameSavedChoices.fingerprint)
        XCTAssertEqual(first.markingRotation, sameSavedChoices.markingRotation)
    }

    func testVisualTraitsStayBoundedAcrossOriginsFamiliesRolesAndStyles() throws {
        for index in 0..<96 {
            let digest = String(format: "%064x", index)
            for family in EvolutionFamily.allCases {
                let role = EvolutionRole.allCases[index % EvolutionRole.allCases.count]
                let style = EvolutionHelpStyle.allCases[index % EvolutionHelpStyle.allCases.count]
                let value = try recipe(origin: digest, family: family, role: role, helpStyle: style)
                XCTAssertTrue(value.accentHue.isFinite && (0...1).contains(value.accentHue))
                XCTAssertTrue(value.horizontalScale.isFinite && (0.94...1.04).contains(value.horizontalScale))
                XCTAssertTrue((2...5).contains(value.markingCount))
                XCTAssertTrue(value.markingRotation.isFinite && value.markingRotation >= 0 && value.markingRotation < 2 * .pi)
                XCTAssertTrue(value.motionSpeed.isFinite && (0.7...1.15).contains(value.motionSpeed))
                XCTAssertEqual(value.fingerprint.utf8.count, 64)
                XCTAssertTrue(value.fingerprint.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
            }
        }
    }

    func testExplanationsUseTheCapturedChoicesAndBasis() throws {
        let original = try recipe()
        let changed = try recipe(family: .relic, role: .keeper, helpStyle: .reflective, basis: .completedPractice)
        let originalByID = Dictionary(uniqueKeysWithValues: original.traitExplanations.map { ($0.id, $0) })
        let changedByID = Dictionary(uniqueKeysWithValues: changed.traitExplanations.map { ($0.id, $0) })
        XCTAssertEqual(original.traitExplanations.count, 5)
        XCTAssertEqual(originalByID["family"]?.value, "Lumen")
        XCTAssertEqual(originalByID["role"]?.value, "Muse")
        XCTAssertEqual(originalByID["help-style"]?.value, "Exploratory")
        XCTAssertEqual(originalByID["basis"]?.value, "Two useful work requests")
        XCTAssertEqual(changedByID["family"]?.value, "Relic")
        XCTAssertEqual(changedByID["role"]?.value, "Keeper")
        XCTAssertEqual(changedByID["help-style"]?.value, "Reflective")
        XCTAssertEqual(changedByID["basis"]?.value, "First completed practice")
        XCTAssertTrue(changedByID["basis"]?.reason.contains("does not increase visual power or establish mastery") == true)
        XCTAssertTrue(originalByID["origin"]?.value.contains(String(origin.prefix(8))) == true)
        XCTAssertEqual(Set(original.traitExplanations.map(\.id)).count, original.traitExplanations.count)
    }

    private func recipe(origin: String? = nil, family: EvolutionFamily = .lumen, role: EvolutionRole = .muse,
                        helpStyle: EvolutionHelpStyle = .exploratory,
                        basis: EvolutionProposalBasis.Kind = .usefulWork) throws -> CompanionAppearanceRecipe {
        try XCTUnwrap(CompanionAppearanceRecipe.make(originDigest: origin ?? self.origin, family: family,
            role: role, helpStyle: helpStyle, basisKind: basis))
    }

    private func encodedObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe())) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CompanionAppearanceRecipe {
        try JSONDecoder().decode(CompanionAppearanceRecipe.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
