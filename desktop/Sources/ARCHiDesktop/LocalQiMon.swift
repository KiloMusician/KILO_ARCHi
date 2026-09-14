import Foundation

/// A name attached to the existing Journey origin. No second individual ID or
/// game-state owner is created when Hampton welcomes KIN.
struct LocalQiMon: Codable, Equatable, Sendable {
    enum Character: String, Codable, Sendable { case kin }
    let character: Character
    let originDigest: String
    let welcomedAt: Date

    var name: String { "KIN" }
    var dedication: String { "Hampton’s first QiMon" }
    /// The identity records his beginning. PersonalQiMonPresentation resolves
    /// a later body through the matching explicitly kept Evolution record.
    var currentBody: CompanionForm { .kinSeed }
    var stageTitle: String { "Core Seed" }
    var isValid: Bool {
        HostedArenaProjection.isDigest(originDigest)
            && welcomedAt.timeIntervalSince1970.isFinite
            && welcomedAt.timeIntervalSince1970 >= 0
    }
}

extension CompanionForm {
    var isKin: Bool { [.kin, .kinSpark, .kinSimple, .kinSeed].contains(self) }
    /// Keep legacy raw identifiers decodable without advertising a person's
    /// companion as a reusable starter skin.
    static var starterChoices: [Self] { allCases.filter { !$0.isKin } }
}
