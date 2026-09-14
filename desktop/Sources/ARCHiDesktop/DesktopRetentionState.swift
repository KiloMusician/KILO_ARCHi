/// Retention is a projection of the existing owners' last successful reads and
/// writes. These states do not inspect disk, save anything, or imply that another
/// process has not subsequently changed a file.
enum PreferenceRetentionState: Equatable, Sendable {
    case unavailable
    case thisVisit
    case changed
    case saved
}

enum EvolutionRetentionState: Equatable, Sendable {
    case notLoaded
    case changed
    case saved
}
