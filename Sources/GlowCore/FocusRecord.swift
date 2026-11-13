import Foundation

/// A credited interval, or a manual adjustment attributed to one calendar day.
/// Consecutive timer ticks from one uninterrupted run share an ID.
public struct FocusRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let duration: TimeInterval
    /// Manual adjustments can belong entirely to the calendar day containing this date,
    /// even when their duration exceeds the time elapsed since midnight.
    public let creditedOn: Date?

    public var endedAt: Date { startedAt.addingTimeInterval(duration) }

    public init(id: UUID = UUID(), startedAt: Date, duration: TimeInterval, creditedOn: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.duration = Self.validDuration(duration)
        self.creditedOn = creditedOn
    }

    private static func validDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite else { return 0 }
        return min(max(duration, 0), 86_400)
    }

    private enum CodingKeys: String, CodingKey { case id, startedAt, duration, creditedOn }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            startedAt: try values.decode(Date.self, forKey: .startedAt),
            duration: try values.decode(TimeInterval.self, forKey: .duration),
            creditedOn: try values.decodeIfPresent(Date.self, forKey: .creditedOn)
        )
    }
}
