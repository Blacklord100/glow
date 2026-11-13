import Foundation
import GlowCore

var checkCount = 0
var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    if !condition() { failures.append(message) }
}

func near(_ actual: Double, _ expected: Double, _ message: String) {
    check(abs(actual - expected) < 0.001, "\(message): expected \(expected), got \(actual)")
}

func append(_ record: FocusRecord?, to ledger: inout FocusLedger) {
    if let record { ledger.append(record) }
}

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, calendar: Calendar = utc) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

let origin = date(2026, 11, 13, 12)

// Accrual, pause, and resume earn exactly the running intervals. Timer ticks coalesce;
// separate running segments remain separate, so history is compact without hiding breaks.
do {
    var session = FocusSession(minutes: 25)
    var ledger = FocusLedger()
    check(session.state == .idle, "New session is idle")
    session.start(at: origin)
    append(session.tick(at: origin.addingTimeInterval(10)), to: &ledger)
    append(session.pause(at: origin.addingTimeInterval(12)), to: &ledger)
    check(session.state == .paused, "Pause changes state")
    check(session.tick(at: origin.addingTimeInterval(100)) == nil, "Paused session earns nothing")
    session.resume(at: origin.addingTimeInterval(200))
    append(session.tick(at: origin.addingTimeInterval(205)), to: &ledger)
    near(session.elapsedSeconds, 17, "Only active seconds count")
    near(ledger.focusSeconds(on: origin, calendar: utc), 17, "Ledger receives active intervals")
    check(ledger.records.count == 2, "Ticks coalesce but resumed segment stays separate")
    near(ledger.records[0].duration, 12, "First segment includes partial tick before pause")
    append(session.end(at: origin.addingTimeInterval(207)), to: &ledger)
    check(session.state == .idle, "End returns to idle")
    near(ledger.focusSeconds(on: origin, calendar: utc), 19, "End accrues final short interval")
    session.start(at: origin.addingTimeInterval(300))
    near(session.elapsedSeconds, 0, "A new start clears the prior session count")
}

// The final timer delivery can overshoot the goal, but credited time cannot.
do {
    var session = FocusSession(minutes: 1)
    var ledger = FocusLedger()
    session.start(at: origin)
    for offset in [15.0, 30, 45, 59, 65] {
        append(session.tick(at: origin.addingTimeInterval(offset)), to: &ledger)
    }
    check(session.state == .completed, "Deadline marks session complete")
    near(session.elapsedSeconds, 60, "Deadline caps earned time")
    near(session.remainingSeconds, 0, "Complete session has no remaining time")
    near(session.progress, 1, "Complete progress is one")
    check(ledger.records.count == 1, "One uninterrupted session uses one record")
    near(ledger.records[0].duration, 60, "History excludes time after the deadline")
    check(session.tick(at: origin.addingTimeInterval(70)) == nil, "Completion stops accrual")
}

// Long gaps and backwards clock changes do not silently count sleep or suspended app time.
do {
    var session = FocusSession()
    session.start(at: origin)
    _ = session.tick(at: origin.addingTimeInterval(5))
    check(session.tick(at: origin.addingTimeInterval(100)) == nil, "Suspension gap is not credited")
    check(session.state == .paused, "Suspension gap pauses the session")
    near(session.elapsedSeconds, 5, "Suspension preserves previously earned time")
    session.resume(at: origin.addingTimeInterval(200))
    check(session.tick(at: origin.addingTimeInterval(199)) == nil, "Clock rollback is not credited")
    check(session.state == .paused, "Clock rollback pauses instead of duplicating time")
}

// One real interval spanning midnight contributes only its overlap to each day.
do {
    let beforeMidnight = date(2026, 11, 13, 23, 59, 50)
    var ledger = FocusLedger(dailyGoalMinutes: 1)
    ledger.append(FocusRecord(startedAt: beforeMidnight, duration: 30))
    near(ledger.focusSeconds(on: beforeMidnight, calendar: utc), 10, "Previous day gets pre-midnight time")
    near(ledger.focusSeconds(on: date(2026, 11, 14), calendar: utc), 20, "Next day gets post-midnight time")
    near(ledger.progress(on: date(2026, 11, 14), calendar: utc), 1.0 / 3, "Daily progress uses daily overlap")
    near(ledger.focusSeconds(on: date(2026, 11, 15), calendar: utc), 0, "Unworked day is empty")
}

// Calendar day duration is not hardcoded to 24 hours: both DST transitions are respected.
do {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    let spring = date(2026, 3, 8, calendar: newYork)
    let fall = date(2026, 11, 1, calendar: newYork)
    let springLedger = FocusLedger(records: [FocusRecord(startedAt: spring, duration: 86_400)])
    near(springLedger.focusSeconds(on: spring, calendar: newYork), 23 * 3_600, "Spring day has 23 hours")
    let fallLedger = FocusLedger(records: [
        FocusRecord(startedAt: fall, duration: 14 * 3_600),
        FocusRecord(startedAt: fall.addingTimeInterval(14 * 3_600), duration: 11 * 3_600)
    ])
    near(fallLedger.focusSeconds(on: fall, calendar: newYork), 25 * 3_600, "Fall day has 25 hours")
}

// Manual time, invalid values and range limits cannot poison history or progress.
do {
    var ledger = FocusLedger(dailyGoalMinutes: -10)
    check(ledger.dailyGoalMinutes == 1, "Goal clamps to positive minutes")
    ledger.dailyGoalMinutes = 99_999
    check(ledger.dailyGoalMinutes == 1_440, "Goal clamps to one day")
    ledger.dailyGoalMinutes = 30
    check(ledger.addManual(minutes: -5, endingAt: origin) == nil, "Negative manual time is ignored")
    check(ledger.addManual(minutes: .nan, endingAt: origin) == nil, "NaN manual time is ignored")
    check(ledger.addManual(minutes: .infinity, endingAt: origin) == nil, "Infinite manual time is ignored")
    ledger.addManual(minutes: 45, endingAt: origin)
    near(ledger.focusSeconds(on: origin, calendar: utc), 2_700, "Manual time adds its intended duration")
    near(ledger.progress(on: origin, calendar: utc), 1, "Progress caps at daily goal")
    check(FocusRecord(startedAt: origin, duration: -.infinity).duration == 0, "Invalid record duration is empty")
    check(FocusSession(minutes: -3).durationMinutes == 1, "Session duration lower bound")
    check(FocusSession(minutes: 999).durationMinutes == 480, "Session duration upper bound")
    let other = FocusRecord(startedAt: origin, duration: 5)
    ledger.append(other)
    check(ledger.records.count == 2, "Manual and session intervals retain separate records")
}

// Persistence preserves earned history while an in-flight timer always restores paused.
do {
    var ledger = FocusLedger(dailyGoalMinutes: 120)
    ledger.addManual(minutes: 17.5, endingAt: origin)
    let data = try JSONEncoder().encode(ledger)
    let restored = try JSONDecoder().decode(FocusLedger.self, from: data)
    check(restored == ledger, "Ledger round-trips without changing history")

    var session = FocusSession(minutes: 25)
    session.start(at: origin)
    _ = session.tick(at: origin.addingTimeInterval(10))
    var recovered = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
    check(recovered.state == .paused, "Running session restores paused")
    near(recovered.elapsedSeconds, 10, "Restored session keeps earned seconds")
    check(recovered.tick(at: origin.addingTimeInterval(3_600)) == nil, "Restoration never credits offline time")
    recovered.resume(at: origin.addingTimeInterval(3_600))
    _ = recovered.tick(at: origin.addingTimeInterval(3_605))
    near(recovered.elapsedSeconds, 15, "Resuming a restored session starts at the new time")

    let malformed = Data("{\"dailyGoalMinutes\":0,\"records\":[]}".utf8)
    let bounded = try JSONDecoder().decode(FocusLedger.self, from: malformed)
    check(bounded.dailyGoalMinutes == 1, "Decoded preferences also validate their bounds")
} catch {
    failures.append("Persistence threw: \(error)")
}

// "Add to today" is explicit day credit, so 60 minutes entered at 00:10 belong
// entirely to today. Older interval-based history still decodes and splits normally.
do {
    let afterMidnight = date(2026, 11, 14, 0, 10)
    var ledger = FocusLedger()
    ledger.addManual(minutes: 60, on: afterMidnight)
    near(ledger.focusSeconds(on: afterMidnight, calendar: utc), 3_600, "Day adjustment credits the full requested time today")
    near(ledger.focusSeconds(on: date(2026, 11, 13), calendar: utc), 0, "Day adjustment does not leak into yesterday")
    near(ledger.focusSeconds(on: date(2026, 11, 15), calendar: utc), 0, "Day adjustment does not leak into tomorrow")
    check(ledger.records.first?.creditedOn == afterMidnight, "Manual day metadata is preserved")
    let restored = try JSONDecoder().decode(FocusLedger.self, from: JSONEncoder().encode(ledger))
    near(restored.focusSeconds(on: afterMidnight, calendar: utc), 3_600, "Day adjustment survives persistence")
    check(ledger.addManual(minutes: -10, on: afterMidnight) == nil, "Negative day adjustment is ignored")
    check(ledger.addManual(minutes: .nan, on: afterMidnight) == nil, "Invalid day adjustment is ignored")

    let oldRecord = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"startedAt\":0,\"duration\":60}"
    let legacy = try JSONDecoder().decode(FocusRecord.self, from: Data(oldRecord.utf8))
    check(legacy.creditedOn == nil, "Existing records decode without new manual metadata")
    near(legacy.duration, 60, "Existing record duration survives migration")
} catch {
    failures.append("Manual day-credit persistence threw: \(error)")
}

if failures.isEmpty {
    print("GlowChecks: \(checkCount) checks passed.")
} else {
    for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
    fputs("GlowChecks: \(failures.count) failures across \(checkCount) checks.\n", stderr)
    exit(1)
}
