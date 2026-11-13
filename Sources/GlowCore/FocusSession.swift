import Foundation

/// A timer independent of UI and wall-clock scheduling. The caller appends each returned
/// record to its ledger and persists the ledger; restoring a session never earns offline time.
public struct FocusSession: Codable, Equatable {
    public enum State: String, Codable { case idle, running, paused, completed }

    public let durationMinutes: Int
    public private(set) var state: State = .idle
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var startedAt: Date?

    private var lastTickAt: Date?
    private var segmentID = UUID()

    public var targetSeconds: TimeInterval { Double(durationMinutes * 60) }
    public var remainingSeconds: TimeInterval { max(0, targetSeconds - elapsedSeconds) }
    public var progress: Double { min(max(elapsedSeconds / targetSeconds, 0), 1) }
    public var isRunning: Bool { state == .running }

    public init(minutes: Int = 25) {
        durationMinutes = min(max(minutes, 1), 480)
    }

    public mutating func start(at date: Date = Date()) {
        elapsedSeconds = 0
        startedAt = date
        lastTickAt = date
        segmentID = UUID()
        state = .running
    }

    /// Call on a regular foreground/background timer (normally each second). A long delivery
    /// gap is treated as sleep or suspension: pause without crediting the unknown interval.
    /// Clock rollback also pauses rather than counting an interval twice.
    @discardableResult
    public mutating func tick(at date: Date = Date(), maximumGap: TimeInterval = 15) -> FocusRecord? {
        guard state == .running, let previous = lastTickAt else { return nil }
        let delta = date.timeIntervalSince(previous)
        let gapLimit = maximumGap.isFinite && maximumGap > 0 ? maximumGap : 15
        guard delta.isFinite, delta >= 0, delta <= gapLimit else {
            state = .paused
            lastTickAt = nil
            return nil
        }
        guard delta > 0 else { return nil }

        let credited = min(delta, remainingSeconds)
        elapsedSeconds += credited
        lastTickAt = date
        if remainingSeconds <= 0 {
            state = .completed
            lastTickAt = nil
        }
        guard credited > 0 else { return nil }
        return FocusRecord(id: segmentID, startedAt: previous, duration: credited)
    }

    @discardableResult
    public mutating func pause(at date: Date = Date()) -> FocusRecord? {
        guard state == .running else { return nil }
        let record = tick(at: date)
        if state != .completed { state = .paused }
        lastTickAt = nil
        return record
    }

    public mutating func resume(at date: Date = Date()) {
        guard state == .paused, remainingSeconds > 0 else { return }
        lastTickAt = date
        segmentID = UUID()
        state = .running
    }

    /// Ends the active session, preserving its earned duration for a final UI summary.
    /// Starting this value again clears the elapsed count and starts a fresh segment.
    @discardableResult
    public mutating func end(at date: Date = Date()) -> FocusRecord? {
        let record = tick(at: date)
        lastTickAt = nil
        state = .idle
        return record
    }

    private enum CodingKeys: String, CodingKey {
        case durationMinutes, state, elapsedSeconds, startedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(minutes: try values.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 25)
        let savedElapsed = try values.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        elapsedSeconds = savedElapsed.isFinite ? min(max(savedElapsed, 0), targetSeconds) : 0
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        let savedState = try values.decodeIfPresent(State.self, forKey: .state) ?? .idle
        state = savedState == .running ? .paused : savedState
        if elapsedSeconds >= targetSeconds { state = .completed }
        lastTickAt = nil
    }
}
