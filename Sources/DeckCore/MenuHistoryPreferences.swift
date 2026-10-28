import Foundation

public struct MenuHistoryPreferences: Codable, Equatable {
    public static let dayRange = 1...36_500
    public let recentDays: Int
    public let frequentDays: Int
    public init(recentDays: Int = 30, frequentDays: Int = 90) {
        self.recentDays = Self.dayRange.contains(recentDays) ? recentDays : 30
        self.frequentDays = Self.dayRange.contains(frequentDays) ? frequentDays : 90
    }
    private enum CodingKeys: String, CodingKey { case recentDays, frequentDays }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recentDays: try c.decodeIfPresent(Int.self, forKey: .recentDays) ?? 30,
                  frequentDays: try c.decodeIfPresent(Int.self, forKey: .frequentDays) ?? 90)
    }
    public static func restore(_ data: Data?) -> Self {
        data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
}
