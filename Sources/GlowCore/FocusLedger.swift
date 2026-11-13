import Foundation

/// Local, date-based focus history. Calendar day boundaries also handle daylight saving changes.
public struct FocusLedger: Codable, Equatable {
    public var dailyGoalMinutes: Int {
        didSet { dailyGoalMinutes = min(max(dailyGoalMinutes, 1), 1_440) }
    }
    public private(set) var records: [FocusRecord]

    public init(dailyGoalMinutes: Int = 240, records: [FocusRecord] = []) {
        self.dailyGoalMinutes = min(max(dailyGoalMinutes, 1), 1_440)
        self.records = records.filter { $0.duration > 0 }
    }

    /// Returns the credited seconds overlapping this calendar day, rather than assigning an
    /// entire cross-midnight session to either its start or end date.
    public func focusSeconds(on date: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return 0 }
        let seconds = records.reduce(0.0) { total, record in
            if let creditedOn = record.creditedOn {
                return total + (calendar.isDate(creditedOn, inSameDayAs: date) ? record.duration : 0)
            }
            let start = max(record.startedAt, day.start)
            let end = min(record.endedAt, day.end)
            return total + max(0, end.timeIntervalSince(start))
        }
        // Manual adjustments may overlap tracked intervals. They add credit, but a day can
        // never claim more time than that actual calendar day contains (23/24/25 hours).
        return min(seconds, day.duration)
    }

    public func progress(on date: Date, calendar: Calendar = .current) -> Double {
        min(max(focusSeconds(on: date, calendar: calendar) / Double(dailyGoalMinutes * 60), 0), 1)
    }

    /// Coalesces only adjoining ticks from the same uninterrupted timer run. Manual entries
    /// and resumed sessions have their own IDs, so their boundaries remain intact.
    public mutating func append(_ record: FocusRecord) {
        guard record.duration > 0 else { return }
        if let previous = records.last,
           previous.creditedOn == nil, record.creditedOn == nil,
           previous.id == record.id,
           abs(previous.endedAt.timeIntervalSince(record.startedAt)) < 0.1,
           previous.duration + record.duration <= 86_400 {
            records[records.count - 1] = FocusRecord(
                id: previous.id,
                startedAt: previous.startedAt,
                duration: previous.duration + record.duration
            )
        } else {
            records.append(record)
        }
    }

    /// Adds an explicit adjustment as an interval ending at the supplied time. Negative,
    /// zero and non-finite inputs are ignored. Entries are limited to 24 hours apiece.
    @discardableResult
    public mutating func addManual(minutes: Double, endingAt: Date) -> FocusRecord? {
        guard minutes.isFinite, minutes > 0 else { return nil }
        let duration = min(minutes, 1_440) * 60
        let record = FocusRecord(startedAt: endingAt.addingTimeInterval(-duration), duration: duration)
        append(record)
        return record
    }

    /// Adds the full adjustment to the chosen day. Use this for an "Add to today"
    /// action; unlike endingAt:, it never moves part of a late-night entry to yesterday.
    @discardableResult
    public mutating func addManual(minutes: Double, on date: Date) -> FocusRecord? {
        guard minutes.isFinite, minutes > 0 else { return nil }
        let duration = min(minutes, 1_440) * 60
        let record = FocusRecord(startedAt: date, duration: duration, creditedOn: date)
        append(record)
        return record
    }

    private enum CodingKeys: String, CodingKey { case dailyGoalMinutes, records }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dailyGoalMinutes: try values.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? 240,
            records: try values.decodeIfPresent([FocusRecord].self, forKey: .records) ?? []
        )
    }
}
