import Foundation

/// A small, explicitly taught presentation choice. These bounded values change
/// the gesture, not the selected passage, a model request, or companion identity.
struct FocusGestureConfiguration: Codable, Equatable, Sendable {
    enum Pace: String, Codable, CaseIterable, Identifiable, Sendable {
        case quick = "Quick", gentle = "Gentle", unhurried = "Unhurried"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    enum Sparkle: String, Codable, CaseIterable, Identifiable, Sendable {
        case none = "None", soft = "Soft", bright = "Bright"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    enum Hold: String, Codable, CaseIterable, Identifiable, Sendable {
        case brief = "Brief", lingering = "Lingering"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    var pace: Pace
    var sparkle: Sparkle
    var hold: Hold

    init(pace: Pace = .gentle, sparkle: Sparkle = .soft, hold: Hold = .brief) {
        self.pace = pace
        self.sparkle = sparkle
        self.hold = hold
    }

    var travelDuration: TimeInterval {
        switch pace {
        case .quick: 0.7
        case .gentle: 1.2
        case .unhurried: 1.8
        }
    }

    var holdDuration: TimeInterval { hold == .brief ? 0.5 : 1.3 }
    var duration: TimeInterval { travelDuration + holdDuration + 0.5 }

    var summary: String {
        let sparkleDescription = sparkle == .none ? "no sparkle" : "a \(sparkle.rawValue.lowercased()) sparkle"
        return "\(pace.rawValue) pointing, \(sparkleDescription), and a \(hold.rawValue.lowercased()) hold."
    }

    private enum CodingKeys: String, CodingKey { case pace, sparkle, hold }
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == Set(["pace", "sparkle", "hold"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "A focus gesture requires only pace, sparkle, and hold."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pace = try values.decode(Pace.self, forKey: .pace)
        sparkle = try values.decode(Sparkle.self, forKey: .sparkle)
        hold = try values.decode(Hold.self, forKey: .hold)
    }
}

enum FocusGesturePurpose: Equatable, Sendable {
    case preview, practice, pointing, explaining
}

/// Playback belongs to one deliberate interaction. It is never persisted, and
/// uses monotonic uptime so clock changes cannot prolong or revive a gesture.
struct FocusGesturePlayback: Equatable, Sendable {
    let id: UUID
    let configuration: FocusGestureConfiguration
    let startedAt: TimeInterval
    let purpose: FocusGesturePurpose
    let spatialPreviewID: UUID?

    init(id: UUID = UUID(), configuration: FocusGestureConfiguration = .init(),
         startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime,
         purpose: FocusGesturePurpose = .preview, spatialPreviewID: UUID? = nil) {
        self.id = id
        self.configuration = configuration
        self.startedAt = startedAt
        self.purpose = purpose
        self.spatialPreviewID = spatialPreviewID
    }

    func isFresh(at now: TimeInterval) -> Bool {
        guard startedAt.isFinite, startedAt >= 0, now.isFinite, now >= startedAt else { return false }
        let deadline = startedAt + configuration.duration
        return deadline.isFinite && deadline > startedAt && now < deadline
    }
}
