import AppKit
import Foundation
import GlowCore
import GlowHardware
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var ledger: FocusLedger
    private(set) var session: FocusSession
    private(set) var now = Date()
    private(set) var hardwareReport: HardwareReport
    private(set) var hardwareEnabled = false
    private(set) var lightingMessage = ""
    private(set) var notice: String?
    var mode: GlowMode { didSet { save(); reconcileLighting() } }
    var cycleDuration: Double { didSet { save(); reconcileLighting() } }
    var sessionMinutes = 25 { didSet { save() } }
    var selectedTab: DashboardTab = .today

    @ObservationIgnored private let hardware: LogoHardware
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lightingTask: Task<Void, Never>?
    @ObservationIgnored private var milestoneTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var saveCounter = 0
    @ObservationIgnored private var isSleeping = false
    @ObservationIgnored private let isPreviewRun: Bool

    enum DashboardTab: String, CaseIterable, Identifiable {
        case today = "Today", lights = "Lights", lab = "Logo Lab"
        var id: String { rawValue }
    }

    private init() {
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--render-previews")
        #else
        let preview = false
        #endif
        isPreviewRun = preview
        let defaults = UserDefaults.standard
        ledger = preview ? FocusLedger() : defaults.data(forKey: "focusLedger").flatMap { try? JSONDecoder().decode(FocusLedger.self, from: $0) } ?? FocusLedger()
        let restoredSession = preview ? FocusSession(minutes: 25) : defaults.data(forKey: "focusSession").flatMap { try? JSONDecoder().decode(FocusSession.self, from: $0) } ?? FocusSession(minutes: 25)
        session = restoredSession
        let savedMinutes = defaults.integer(forKey: "sessionMinutes")
        sessionMinutes = restoredSession.state == .paused ? restoredSession.durationMinutes : ([25, 45, 60].contains(savedMinutes) ? savedMinutes : 25)
        mode = preview ? .dailyCharge : GlowMode(rawValue: defaults.string(forKey: "glowMode") ?? "") ?? .dailyCharge
        let savedCycle = defaults.double(forKey: "cycleDuration")
        cycleDuration = (3...12).contains(savedCycle) ? savedCycle : 6
        let device = LogoHardware()
        hardware = device
        hardwareReport = device.report
        if !preview {
            let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(clock, forMode: .common)
            timer = clock
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.wake() }
            })
        }
    }

    var todaySeconds: TimeInterval { ledger.focusSeconds(on: now) }
    var dailyProgress: Double { ledger.progress(on: now) }
    var goalMinutes: Int { ledger.dailyGoalMinutes }
    var isRunning: Bool { session.state == .running }
    var isPaused: Bool { session.state == .paused }
    var sessionActive: Bool { isRunning || isPaused }
    var percentLabel: String { "\(Int(dailyProgress * 100))%" }
    var hardwareLabel: String { hardwareReport.directControlAvailable ? "Logo available" : "Logo preview only" }

    func setGoal(minutes: Int) {
        ledger.dailyGoalMinutes = min(720, max(30, minutes))
        save()
    }

    func toggleSession() {
        notice = nil
        now = Date()
        switch session.state {
        case .running:
            credit(session.pause(at: now))
        case .paused:
            session.resume(at: now)
        case .idle, .completed:
            session = FocusSession(minutes: sessionMinutes)
            session.start(at: now)
        }
        save()
    }

    func endSession() {
        credit(session.end(at: Date()))
        session = FocusSession(minutes: sessionMinutes)
        notice = "Session saved. Take a breath."
        save()
    }

    func addTime(minutes: Double) {
        guard minutes.isFinite, minutes > 0, minutes <= 720 else { return }
        now = Date()
        let previousQuarter = Int(dailyProgress * 4)
        ledger.addManual(minutes: minutes, on: now)
        notice = "Added \(Int(minutes)) minutes to your day."
        if Int(dailyProgress * 4) > previousQuarter { milestonePulse() }
        save()
    }

    func dismissNotice() { notice = nil }

    func setHardwareEnabled(_ enabled: Bool) {
        hardwareEnabled = enabled && hardwareReport.directControlAvailable && !isPreviewRun
        reconcileLighting()
    }

    func refreshHardware() {
        hardware.refresh()
        hardwareReport = hardware.report
        if !hardwareReport.directControlAvailable { hardwareEnabled = false }
        reconcileLighting()
    }

    func shutdown() {
        credit(session.pause(at: Date()))
        save()
        timer?.invalidate()
        lightingTask?.cancel()
        milestoneTask?.cancel()
        hardware.restore()
    }

    private func tick() {
        now = Date()
        let before = Int(dailyProgress * 4)
        let wasRunning = isRunning
        credit(session.tick(at: now))
        if wasRunning && session.state == .completed {
            notice = "Focus complete. Your minutes are saved."
            save()
            milestonePulse()
        } else if wasRunning && isPaused {
            notice = "Timer paused after an interruption. Resume when you're ready."
            save()
        } else if Int(dailyProgress * 4) > before {
            notice = dailyProgress >= 1 ? "Daily goal reached. Nicely done." : "Another quarter of your daily goal."
            milestonePulse()
        }
        saveCounter += 1
        if saveCounter >= 15 { save(); saveCounter = 0 }
    }

    private func credit(_ record: FocusRecord?) {
        if let record { ledger.append(record) }
    }

    private func suspend() {
        isSleeping = true
        if isRunning {
            credit(session.pause(at: Date()))
            notice = "Focus paused while your Mac was away."
        }
        lightingTask?.cancel()
        milestoneTask?.cancel()
        hardware.restore()
        save()
    }

    private func wake() {
        isSleeping = false
        now = Date()
        reconcileLighting()
    }

    private func reconcileLighting() {
        lightingTask?.cancel()
        milestoneTask?.cancel()
        hardware.restore()
        lightingMessage = ""
        guard hardwareEnabled, !isSleeping else { return }
        switch mode {
        case .breathe, .pulse:
            let effect: HardwareEffect = mode == .breathe ? .breathe : .pulse
            lightingTask = Task { [weak self] in
                guard let self else { return }
                do { try await hardware.start(effect: effect, cycleDuration: cycleDuration) }
                catch is CancellationError { }
                catch { lightingMessage = error.localizedDescription; hardwareEnabled = false; hardware.restore() }
            }
        case .off:
            do { try hardware.turnOff() }
            catch { lightingMessage = error.localizedDescription; hardwareEnabled = false }
        case .dailyCharge, .automatic:
            break
        }
    }

    private func milestonePulse() {
        guard mode == .dailyCharge, hardwareEnabled, !isSleeping else { return }
        lightingTask?.cancel()
        milestoneTask?.cancel()
        hardware.restore()
        lightingTask = Task { [weak self] in
            guard let self else { return }
            do { try await hardware.start(effect: .pulse, cycleDuration: 4) }
            catch is CancellationError { }
            catch { lightingMessage = error.localizedDescription; hardware.restore() }
        }
        milestoneTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self else { return }
            lightingTask?.cancel()
            hardware.restore()
        }
    }

    private func save() {
        guard !isPreviewRun else { return }
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "focusLedger") }
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: "focusSession") }
        defaults.set(mode.rawValue, forKey: "glowMode")
        defaults.set(cycleDuration, forKey: "cycleDuration")
        defaults.set(sessionMinutes, forKey: "sessionMinutes")
    }
}
