import AppKit
import CryptoKit
import SwiftUI

/// Alpha presentation permits bounded color raster rounding, while preserving
/// every alpha sample and the frame exactly. PNG byte identity is separate.
struct NaturalPresentationComparison {
    static let acceptanceDescription = "Exact dimensions, full alpha channel and natural traits; maximum premultiplied RGB difference <= 2/255 and mean <= 0.1/255. PNG byte equality is reported separately and is not required by this Alpha presentation bound."
    let exactPNGBytes: Bool
    let dimensionsEqual: Bool
    let alphaEqual: Bool
    let maximumRGBDifference: Double
    let meanRGBDifference: Double

    var withinAlphaPresentationBound: Bool {
        dimensionsEqual && alphaEqual && maximumRGBDifference <= 2 && meanRGBDifference <= 0.1
    }

    var receipt: [String: Any] {
        ["exactPNGBytes": exactPNGBytes, "dimensionsEqual": dimensionsEqual, "fullAlphaEqual": alphaEqual,
         "measurementMethod": "Both PNGs decoded at native dimensions into 8-bit premultiplied sRGB RGBA; no resizing or interpolation.",
         "maximumPremultipliedRGBDifferenceByteUnits": maximumRGBDifference,
         "meanPremultipliedRGBDifferenceByteUnits": meanRGBDifference,
         "withinAlphaPresentationBound": withinAlphaPresentationBound]
    }

    static func compare(_ first: Data, _ second: Data) throws -> Self {
        let a = try pixels(first), b = try pixels(second)
        guard a.width == b.width, a.height == b.height else {
            return Self(exactPNGBytes: first == second, dimensionsEqual: false, alphaEqual: false,
                maximumRGBDifference: 255, meanRGBDifference: 255)
        }
        var maximum = 0, total = 0, sameAlpha = true
        for index in stride(from: 0, to: a.bytes.count, by: 4) {
            sameAlpha = sameAlpha && a.bytes[index + 3] == b.bytes[index + 3]
            for channel in 0..<3 {
                let difference = abs(Int(a.bytes[index + channel]) - Int(b.bytes[index + channel]))
                maximum = max(maximum, difference)
                total += difference
            }
        }
        return Self(exactPNGBytes: first == second, dimensionsEqual: true, alphaEqual: sameAlpha,
            maximumRGBDifference: Double(maximum), meanRGBDifference: Double(total) / Double(a.width * a.height * 3))
    }

    private static func pixels(_ png: Data) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        guard let bitmap = NSBitmapImageRep(data: png), let image = bitmap.cgImage,
              image.width > 0, image.height > 0, image.width <= 2048, image.height <= 2048,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NSError(domain: "NaturalPresentationComparison", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Native PNG comparison could not decode a bounded image."])
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else {
            throw NSError(domain: "NaturalPresentationComparison", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Native PNG comparison could not read premultiplied pixels."])
        }
        return (image.width, image.height, bytes)
    }
}

/// Explicit offscreen design export. Uses local synthetic state and never reads
/// the running GUI's preferences, shared documents, or assistant connections.
@MainActor
enum EvolutionVisualDiagnostics {
    static func renderStarterStudy(directory: URL) -> Bool {
        _ = NSApplication.shared
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let original = CompanionPresenceArt.png(form: .companion, family: nil),
                  let pearl = CompanionPresenceArt.png(form: .companion, family: nil, treatment: .pearlStudy) else { return false }
            try original.write(to: directory.appendingPathComponent("original-native.png"), options: .atomic)
            try pearl.write(to: directory.appendingPathComponent("pearl-native.png"), options: .atomic)
            let result: [String: Any] = ["assetAvailable": CompanionVisualAsset.image != nil,
                "assetPath": CompanionVisualAsset.resourceURL?.path ?? "missing",
                "bundle": Bundle.main.bundleURL.path,
                "appearanceID": CompanionVisualAsset.appearanceID(form: .companion, family: nil, treatment: .pearlStudy),
                "originalAndPearlDiffer": original != pearl,
                "scope": "Offscreen snapshots from the packaged native selector; no live user input or data."]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("starter-art.json"), options: .atomic)
            return CompanionVisualAsset.image == nil ? original == pearl : original != pearl
        } catch { return false }
    }

    static func run(directory: URL) -> Bool {
        _ = NSApplication.shared
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try render(EvolutionFormSheet(), to: directory.appendingPathComponent("form-studies.png"), width: 1080)
            let client = EvolutionVisualNoInferenceClient()
            let initialFixture = directory.appendingPathComponent("form-fixture-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: initialFixture, withIntermediateDirectories: true)
            let store = CompanionStore(preferenceURL: initialFixture.appendingPathComponent("synthetic-preferences.json"),
                assistant: client, assistantFactory: { _, _ in client })
            let before = EvolutionReviewPage(store: store, note: "SYNTHETIC INITIAL STATE · NO PREFERENCES OR WORK RECORDS")
            try renderHosted(before, to: directory.appendingPathComponent("evolution-start.png"), width: 850)
            store.evolution.confirmFamily(.fen)
            store.evolution.proposeEvolution()
            try renderHosted(EvolutionReviewPage(store: store, note: "SYNTHETIC OPTIONAL FORM CHOICE · NO TASK OR PREFERENCE REQUIREMENT"),
                       to: directory.appendingPathComponent("evolution-ready.png"), width: 850)
            guard client.attemptedInvocations == 0, try renderNaturalStudy(directory: directory) else { return false }
            print("PASS: offscreen native initial-companion and optional-form views exported. All state is synthetic; no native input acceptance or real user knowledge is claimed.")
            return true
        } catch {
            print("FAIL: Evolution design export: \(error.localizedDescription)")
            return false
        }
    }

    private static func renderNaturalStudy(directory: URL) throws -> Bool {
        var checks: [String: Bool] = [:]
        var renderHashes: [String: String] = [:]
        var renderContexts: [String: [String: Any]] = [:]
        var byteEquality: [String: Bool] = [:]
        var pixelComparisons: [String: [String: Any]] = [:]
        var variationReferences: [[String: Any]] = []
        var failure: String?
        let client = EvolutionVisualNoInferenceClient()
        let fixtureDirectory = directory.appendingPathComponent("natural-fixture-\(UUID().uuidString)", isDirectory: true)
        let preferenceURL = fixtureDirectory.appendingPathComponent("synthetic-preferences.json")
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            let origins = ["1", "2", "3"].map { String(repeating: $0, count: 64) }
            let variations = try origins.map { origin in
                guard let variation = CompanionNaturalVariation.make(originDigest: origin) else {
                    throw NaturalStudyFailure.invalidState("Synthetic natural variation could not be created.")
                }
                return variation
            }
            func captureNaturalImage(_ name: String, variation: CompanionNaturalVariation?) throws -> Data {
                guard let data = CompanionPresenceArt.png(form: .companion, family: nil,
                    treatment: .pearlStudy, naturalVariation: variation) else {
                    throw NaturalStudyFailure.invalidState("Native comparison capture \(name) was unavailable.")
                }
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                renderHashes[name] = digest(data)
                renderContexts[name] = nativeRenderContextMetadata()
                return data
            }
            variationReferences = variations.enumerated().map { index, variation in
                ["fixture": "synthetic-\(index + 1)", "originDigest": variation.originDigest,
                 "fingerprint": variation.fingerprint, "horizontalScale": variation.horizontalScale,
                 "hueDegrees": variation.hueDegrees, "markingCount": variation.markingCount,
                 "markingRotation": variation.markingRotation]
            }
            checks["distinctVariationFingerprintsInThisFixture"] = Set(variations.map(\.fingerprint)).count == 3
            checks["sameOriginReproducesVariation"] = CompanionNaturalVariation.make(originDigest: origins[0]) == variations[0]
            guard let originalBefore = CompanionPresenceArt.png(form: .companion, family: nil),
                  let pearlBefore = CompanionPresenceArt.png(form: .companion, family: nil, treatment: .pearlStudy) else {
                throw NaturalStudyFailure.invalidState("Native baseline rendering was unavailable.")
            }
            try pearlBefore.write(to: directory.appendingPathComponent("natural-baseline.png"), options: .atomic)
            renderHashes["natural-baseline.png"] = digest(pearlBefore)
            var bodyHashes: [String] = []
            var firstBody: Data?
            for (index, variation) in variations.enumerated() {
                guard let data = CompanionPresenceArt.png(form: .companion, family: nil,
                    treatment: .pearlStudy, naturalVariation: variation) else {
                    throw NaturalStudyFailure.invalidState("A naturally varied native companion could not be rendered.")
                }
                let name = "natural-individual-\(index + 1).png"
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                renderHashes[name] = digest(data)
                renderContexts[name] = nativeRenderContextMetadata()
                bodyHashes.append(digest(data))
                if index == 0 { firstBody = data }
            }
            guard let firstBody else {
                throw NaturalStudyFailure.invalidState("The initial individual comparison was unavailable.")
            }
            checks["distinctRenderedCompanionsInThisFixture"] = Set(bodyHashes).count == 3
            _ = try captureNaturalImage("natural-before-sheet-repeat.png", variation: variations[0])
            try render(EvolutionNaturalFormSheet(variations: variations),
                to: directory.appendingPathComponent("natural-forms.png"), width: 1080)
            _ = try captureNaturalImage("natural-after-sheet-repeat.png", variation: variations[0])

            let store = CompanionStore(preferenceURL: preferenceURL, assistant: client,
                assistantFactory: { _, _ in client })
            store.preferences.visualTreatment = .pearlStudy
            store.evolution.observeJourneyOrigin(origins[0])
            _ = try captureNaturalImage("natural-after-store-repeat.png", variation: store.evolution.naturalVariation)
            checks["naturalVariationBeforePreferencesOrTasks"] = store.evolution.naturalVariation == variations[0]
                && store.evolution.confirmedRole == nil && store.evolution.confirmedHelpStyle == nil
                && store.evolution.confirmedFamily == nil && store.evolution.usefulReceipts.isEmpty
                && store.evolution.reviewedPractices.isEmpty && store.evolution.activeFamily == nil
            checks["observedJourneyNeedsNoManualVariationBinding"] = store.evolution.practiceJourneyOriginDigest == nil
                && store.evolution.naturalVariation != nil
            try renderHosted(EvolutionReviewPage(store: store,
                note: "SYNTHETIC INDIVIDUAL · INITIAL PEARL COMPANION · NO SETTINGS OR TASKS REQUIRED"),
                to: directory.appendingPathComponent("natural-companion.png"), width: 850)
            _ = try captureNaturalImage("natural-after-host-repeat.png", variation: store.evolution.naturalVariation)

            store.evolution.confirmRole(.muse)
            store.evolution.confirmHelpStyle(.exploratory)
            checks["roleAndHelpDoNotChangeNaturalVariation"] = store.evolution.naturalVariation == variations[0]
            let afterHelp = try captureNaturalImage("natural-after-help.png", variation: store.evolution.naturalVariation)
            let helpComparison = try NaturalPresentationComparison.compare(firstBody, afterHelp)
            byteEquality["roleAndHelpDoNotChangeRenderedBody"] = helpComparison.exactPNGBytes
            pixelComparisons["afterHelp"] = helpComparison.receipt
            checks["roleAndHelpPreserveVisibleBody"] = helpComparison.withinAlphaPresentationBound
            store.evolution.revoke(.role)
            store.evolution.revoke(.helpStyle)
            store.evolution.confirmFamily(.lumen)
            guard let proposal = store.evolution.proposeEvolution() else {
                throw NaturalStudyFailure.invalidState("Family choice alone did not produce an optional appearance proposal.")
            }
            checks["familyChoiceAloneAllowsProposal"] = store.evolution.confirmedRole == nil
                && store.evolution.confirmedHelpStyle == nil && store.evolution.usefulReceipts.isEmpty
                && store.evolution.reviewedPractices.isEmpty && store.evolution.practiceJourneyOriginDigest == nil
                && proposal.basis.kind == .appearanceChoice && proposal.appearanceRecipe == nil
            checks["proposalDoesNotApplyAppearance"] = store.evolution.activeFamily == nil
                && store.evolution.naturalVariation == variations[0]
            try renderHosted(EvolutionReviewPage(store: store,
                note: "SYNTHETIC OPTIONAL LUMEN CHOICE · NO EARNED UPGRADE OR LEARNING CLAIM"),
                to: directory.appendingPathComponent("natural-choice.png"), width: 850)
            checks["reviewedAppearanceChoiceKept"] = store.evolution.keepEvolution(proposal)
            checks["keptChoicePreservesNaturalIndividual"] = store.evolution.activeFamily == .lumen
                && store.evolution.keptBasis?.kind == .appearanceChoice && store.evolution.keptAppearanceRecipe == nil
                && store.evolution.naturalVariation == variations[0]
            checks["originExplicitlyBoundForPersistence"] = store.evolution.bindPracticeJourney(origins[0])
            checks["explicitSaveSucceeded"] = store.evolution.save()
            guard let saveURL = store.evolution.saveURL, checks["explicitSaveSucceeded"] == true else {
                throw NaturalStudyFailure.invalidState("Synthetic appearance save did not complete.")
            }
            let savedBytes = try Data(contentsOf: saveURL)
            let savedObject = try JSONSerialization.jsonObject(with: savedBytes) as? [String: Any]
            checks["saveUsesV4Schema"] = savedObject?["schema"] as? String == "archi-companion-evolution/v4"
            let loaded = EvolutionStore(origin: .companion, saveURL: saveURL)
            checks["freshStoreDoesNotImplicitlyLoad"] = loaded.activeFamily == nil && loaded.history.isEmpty
            checks["explicitLoadSucceeded"] = loaded.load()
            checks["loadPreservesActiveChoice"] = loaded.activeFamily == .lumen && loaded.keptBasis?.kind == .appearanceChoice
                && loaded.keptAppearanceRecipe == nil
            checks["loadPreservesHistory"] = loaded.history == store.evolution.history
            checks["loadPreservesBoundOrigin"] = loaded.practiceJourneyOriginDigest == origins[0]
            checks["loadRestoresNaturalVariationFromBoundOrigin"] = loaded.naturalVariation == variations[0]
            loaded.observeJourneyOrigin(origins[0])
            loaded.returnToStarter()
            checks["returnRestoresStarterAndRetainsNaturalIndividual"] = loaded.activeFamily == nil
                && loaded.activeAppearanceRecipe == nil && loaded.naturalVariation == variations[0]
                && loaded.observedJourneyOriginDigest == origins[0]
            let afterReturn = try captureNaturalImage("natural-after-return.png", variation: loaded.naturalVariation)
            let returnComparison = try NaturalPresentationComparison.compare(firstBody, afterReturn)
            byteEquality["returnedIndividualRendersIdentically"] = returnComparison.exactPNGBytes
            pixelComparisons["afterReturn"] = returnComparison.receipt
            checks["returnedIndividualPreservesVisibleBody"] = returnComparison.withinAlphaPresentationBound
            checks["returnRetainsAppearanceChoiceHistory"] = loaded.history.contains { $0.kind == .kept && $0.family == .lumen }
                && loaded.history.last?.kind == .returned
            checks["returnDoesNotAutosave"] = try Data(contentsOf: saveURL) == savedBytes
            checks["unvariedOriginalBaselineUnchanged"] = CompanionPresenceArt.png(form: .companion, family: nil) == originalBefore
            checks["unvariedPearlBaselineUnchanged"] = CompanionPresenceArt.png(form: .companion, family: nil,
                treatment: .pearlStudy) == pearlBefore
            checks["noUsefulnessOrPracticeRecordsFabricated"] = store.evolution.usefulReceipts.isEmpty
                && store.evolution.reviewedPractices.isEmpty && loaded.usefulReceipts.isEmpty && loaded.reviewedPractices.isEmpty
            for name in ["natural-forms.png", "natural-companion.png", "natural-choice.png"] {
                renderHashes[name] = digest(try Data(contentsOf: directory.appendingPathComponent(name)))
            }
        } catch {
            failure = error.localizedDescription
        }
        checks["noAssistantConnectionOrReplyAttempted"] = client.attemptedInvocations == 0
        checks["noNativePreferenceFileWritten"] = !FileManager.default.fileExists(atPath: preferenceURL.path)
        let passed = failure == nil && checks.values.allSatisfy { $0 }
        var report: [String: Any] = [
            "schema": "archi-natural-visual-diagnostics/v1", "passed": passed, "checks": checks,
            "variations": variationReferences, "renderSHA256": renderHashes, "renderContexts": renderContexts,
            "byteEquality": byteEquality, "pixelComparisons": pixelComparisons,
            "presentationAcceptance": NaturalPresentationComparison.acceptanceDescription,
            "form": CompanionForm.companion.rawValue, "treatment": CompanionVisualTreatment.pearlStudy.rawValue,
            "syntheticStateDirectory": fixtureDirectory.lastPathComponent,
            "assistantInvocations": client.attemptedInvocations,
            "scope": "Offscreen native synthetic fixtures: three origins rendered as the current Companion/Pearl, immediate variation before preferences or tasks, and an optional Lumen choice with explicit Save/Load/Return. No real user preferences, Journey, documents, model calls, provider sessions, or live UI input. This validates initial cosmetic individuality and appearance choice, not earned developmental stages, personal learning, exclusive artwork, ownership, or cross-device acceptance."
        ]
        if let failure { report["failure"] = failure }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("natural-diagnostics.json"), options: .atomic)
        print("\(passed ? "PASS" : "FAIL"): natural individual rendering and optional appearance Save/Load/Return diagnostics. No inference or fabricated work records.")
        return passed
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func nativeRenderContextMetadata() -> [String: Any] {
        let asset = CompanionVisualAsset.image
        let representations: [[String: Any]] = asset?.representations.map { representation in
            ["type": String(describing: type(of: representation)), "pixelsWide": representation.pixelsWide,
             "pixelsHigh": representation.pixelsHigh, "width": Double(representation.size.width),
             "height": Double(representation.size.height)]
        } ?? []
        return ["applicationAppearance": NSApplication.shared.effectiveAppearance.name.rawValue,
                "screenBackingScale": NSScreen.main?.backingScaleFactor ?? 0,
                "assetWidth": Double(asset?.size.width ?? 0), "assetHeight": Double(asset?.size.height ?? 0),
                "assetRepresentations": representations]
    }

    private enum NaturalStudyFailure: LocalizedError {
        case invalidState(String)
        var errorDescription: String? {
            switch self { case .invalidState(let message): return message }
        }
    }

    private static func render<V: View>(_ view: V, to url: URL, width: CGFloat) throws {
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light))
        renderer.scale = 1.5
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    /// ImageRenderer cannot draw NSView-backed Picker/borderless controls. Cache
    /// the hosting view instead, without reading screen pixels or showing a window.
    private static func renderHosted<V: View>(_ view: V, to url: URL, width: CGFloat) throws {
        let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light))
        let height = host.fittingSize.height
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        window.close()
    }
}

@MainActor
private final class EvolutionVisualNoInferenceClient: AssistantClient {
    private(set) var attemptedInvocations = 0
    func connect() async throws { attemptedInvocations += 1; throw AssistantFailure.protocolError }
    func reply(to request: AssistantRequest, onEvent: @escaping @MainActor (AssistantEvent) -> Void) async throws {
        attemptedInvocations += 1
        throw AssistantFailure.protocolError
    }
    func disconnect() {}
}

private struct EvolutionNaturalFormSheet: View {
    let variations: [CompanionNaturalVariation]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ARCHi / NATURAL INDIVIDUAL STUDY").font(.system(size: 11, weight: .medium)).tracking(2)
                .foregroundStyle(.cyan.opacity(0.8))
            Text("One Pearl family.").font(.system(size: 36, weight: .medium, design: .rounded))
            Text("SYNTHETIC ORIGINS · THE CURRENT COMPANION · NO PREFERENCES OR TASKS · MOTION HELD STILL")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    CompanionPresenceArt(form: .companion, family: nil, size: 190, reduceMotion: true,
                        treatment: .pearlStudy).frame(maxWidth: .infinity)
                    Text("Pearl baseline").font(.system(size: 16, weight: .medium))
                    Text("Approved base artwork").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    Text("The unchanged rendering before a Journey's small individual variations.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineSpacing(3)
                        .frame(minHeight: 68, alignment: .top)
                }.padding(16).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                ForEach(Array(variations.enumerated()), id: \.offset) { index, variation in
                    VStack(alignment: .leading, spacing: 12) {
                        CompanionPresenceArt(form: .companion, family: nil, size: 190, reduceMotion: true,
                            treatment: .pearlStudy, naturalVariation: variation).frame(maxWidth: .infinity)
                        Text("Individual \(index + 1)").font(.system(size: 16, weight: .medium))
                        Text("Same family, from the start")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(variation.markingCount) small markings")
                            Text("Origin \(variation.originDigest.prefix(8))").font(.system(size: 10, design: .monospaced))
                            Text("Details \(variation.fingerprint.prefix(10))").font(.system(size: 10, design: .monospaced))
                        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            .frame(minHeight: 68, alignment: .top)
                    }.padding(16).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            Text("Each synthetic Journey supplies small, stable differences in tint, proportions, and markings within the same recognizable Pearl body. No role, help style, task count, or appearance upgrade creates this individuality.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).lineSpacing(4)
        }.padding(40).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.055, green: 0.09, blue: 0.14), Color(red: 0.1, green: 0.1, blue: 0.17)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

@MainActor
private struct EvolutionReviewPage: View {
    let store: CompanionStore
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("ARCHi / EVOLUTION").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(ArchiPalette.violet)
            Text("Becoming, together.").font(.system(size: 32, weight: .medium, design: .rounded))
            Text(note).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            EvolutionWorkspace(store: store, evolution: store.evolution)
        }.padding(32).background(Color(red: 0.97, green: 0.96, blue: 0.95))
    }
}

private struct EvolutionFormSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 26) {
                CompanionArt(form: .companion, size: 132, reduceMotion: true)
                VStack(alignment: .leading, spacing: 9) {
                    Text("ARCHi  /  OPTIONAL FORM STUDIES").font(.system(size: 11, weight: .medium)).tracking(3).foregroundStyle(.cyan.opacity(0.75))
                    Text("Your individual.\nAppearance choices.").font(.system(size: 39, weight: .medium, design: .rounded))
                    Text("These larger form changes are optional studies, available whenever you choose.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
                ForEach(EvolutionFamily.allCases) { family in
                    VStack(alignment: .leading, spacing: 10) {
                        EvolvedCompanionArt(family: family, size: 214, reduceMotion: true).frame(maxWidth: .infinity)
                        Text(family.title.uppercased()).font(.system(size: 14, weight: .medium)).tracking(3)
                        Text(family.summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineSpacing(4).frame(height: 44, alignment: .top)
                    }.padding(20)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
                }
            }
            HStack(spacing: 14) {
                Label("Choose an appearance", systemImage: "paintpalette")
                Image(systemName: "arrow.right")
                Text("Review the form")
                Image(systemName: "arrow.right")
                Text("Keep or return")
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
            Text("LOCAL NATIVE RENDER · PROCEDURAL FORM STUDIES · NO MODEL TRAINING OR NEW ABILITIES")
                .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(.white.opacity(0.4))
        }.padding(40).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.055, green: 0.09, blue: 0.14), Color(red: 0.1, green: 0.1, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
