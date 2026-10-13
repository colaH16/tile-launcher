import Foundation

public struct OptionReopenPreferences: Codable, Equatable {
    public static let intervalRange: ClosedRange<TimeInterval> = 0.1...2.0
    public static let defaultInterval: TimeInterval = 0.8
    public let enabled: Bool
    public let interval: TimeInterval

    public init(enabled: Bool = true, interval: TimeInterval = defaultInterval) {
        self.enabled = enabled
        self.interval = Self.intervalRange.contains(interval) ? interval : Self.defaultInterval
    }

    private enum CodingKeys: String, CodingKey { case enabled, interval }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  interval: try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? Self.defaultInterval)
    }
    public static func restore(_ data: Data?) -> Self {
        data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
}
