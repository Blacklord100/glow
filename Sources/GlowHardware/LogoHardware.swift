import AppKit
import CoreGraphics
import Foundation

/// Opt-in, whole-logo control. Construction and refresh are read-only. Nothing is
/// written until start or turnOff is called explicitly by the application.
@MainActor
public final class LogoHardware {
    public private(set) var report: HardwareReport

    private struct Session {
        let client: CoreBrightnessClient
        let originalMode: Int
        let generation: UInt64
    }

    private var session: Session?
    // Keep the original setting if cleanup fails. This is deliberately separate
    // from the active session so its cancelled animation can never resume.
    private var pendingRecovery: Session?
    private var generation: UInt64 = 0
    private var displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var lastRestoreIssue: String?

    public init() {
        report = HardwareReport(modelIdentifier: HardwareInventory.modelIdentifier,
                                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                logoDetected: false, directControlAvailable: false,
                                candidateNodes: [], summary: "Checking logo hardware…", details: "")
        refresh()
        observeLifecycle()
    }

    deinit {
        // The application calls restore before releasing this controller and when
        // quitting. Deinit cannot promise execution during force-quit or power loss.
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in applicationObservers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Enumerates only an allowlist of relevant registry data. No register writes,
    /// root commands, NVRAM changes or device opening are performed by this scan.
    public func refresh() {
        let inventory = HardwareInventory.read()
        let client = inventory.logoDetected ? (session?.client ?? CoreBrightnessClient()) : nil
        let supported = inventory.logoDetected && client != nil
        let conflicts = competingApplications()
        let summary: String
        if !inventory.logoDetected {
            summary = "Preview only: this Mac has no detected illuminated-logo device."
        } else if !supported {
            summary = "Logo detected, but safe direct control is unavailable on this macOS version."
        } else if !conflicts.isEmpty {
            summary = "Quit \(conflicts.joined(separator: ", ")) to enable logo control."
        } else {
            summary = "Whole-logo effects are available. Individual LED control is unverified."
        }

        var details = [
            "Model: \(HardwareInventory.modelIdentifier)",
            "System: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Scan: read-only; names, paths and selected PWM/channel properties only.",
            "Known logo service detected: \(inventory.logoDetected ? "yes" : "no")",
            "Known control interface and keyboard correction detected: \(supported ? "yes" : "no")",
            "Individual LEDs: not verified. A scalar interface or a missing node does not establish physical wiring.",
            "The device uses a shared diffuser; usable spatial patterns require a separate hardware experiment.",
            "This build supports bounded fades only. It does not set unknown channel values or hold a brightness level indefinitely.",
            "Experimental hardware support: physical effects have not been validated on a compatible MacBook for this release.",
            "Normal stop attempts to restore the previous on/off setting. Force-quit or power loss can leave that macOS setting changed; there is no automatic startup write."
        ]
        if !conflicts.isEmpty { details.append("Other logo utilities running: \(conflicts.joined(separator: ", "))") }
        if let issue = lastRestoreIssue { details.append("Last restore issue: \(issue)") }
        if inventory.nodes.isEmpty {
            details.append("No matching PWM services or logo-related device-tree nodes were found.")
        } else {
            for node in inventory.nodes {
                details.append("\n[\(node.plane)] \(node.name)\n\(node.path)")
                details.append(contentsOf: node.properties.map { "  " + $0 })
            }
        }
        report = HardwareReport(modelIdentifier: HardwareInventory.modelIdentifier,
                                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                logoDetected: inventory.logoDetected,
                                directControlAvailable: supported && conflicts.isEmpty,
                                candidateNodes: inventory.nodes.map { "[\($0.plane)] \($0.path)" },
                                summary: summary, details: details.joined(separator: "\n"))
    }

    /// Runs until cancelled, restored or a lifecycle event stops the session.
    /// Callers should cancel their task and call restore when changing mode.
    public func start(effect: HardwareEffect, cycleDuration: Double) async throws {
        try Task.checkCancellation()
        guard cycleDuration.isFinite, (2...20).contains(cycleDuration) else {
            throw HardwareControlError.invalidDuration
        }
        let active = try beginSession()
        defer { if session?.generation == active.generation { restore() } }
        if active.originalMode == 0 {
            try active.client.set(NSNumber(value: 2), key: "LEBacklightMode")
            try await wait(0.1, session: active)
            guard active.client.mode == 2 else { throw HardwareControlError.commandRejected("LEBacklightMode") }
        }

        // Establish a known direction without changing panel brightness. Subsequent
        // steps alternate and use the daemon's own bounded fade animation.
        try active.client.fade(lit: false, duration: 0.25, keepKeyboardLit: true)
        try await wait(0.3, session: active)

        while true {
            try check(active)
            if let competitor = competingApplications().first {
                throw HardwareControlError.competingApplication(competitor)
            }
            switch effect {
            case .breathe:
                try await fade(true, duration: cycleDuration * 0.55, session: active)
                try await fade(false, duration: cycleDuration * 0.45, session: active)
            case .pulse:
                try await fade(true, duration: cycleDuration * 0.18, session: active)
                try await wait(cycleDuration * 0.08, session: active)
                try await fade(false, duration: cycleDuration * 0.32, session: active)
                try await wait(cycleDuration * 0.42, session: active)
            }
        }
    }

    /// A temporary off state: restore returns the original mode. This is an
    /// explicit action, never a fallback when an unsupported interface is found.
    public func turnOff() throws {
        let active = try beginSession()
        do {
            try active.client.set(NSNumber(value: 0), key: "LEBacklightMode")
            guard active.client.mode == 0 else { throw HardwareControlError.commandRejected("LEBacklightMode") }
        } catch {
            restore()
            throw error
        }
    }

    /// Idempotent cleanup. It restores the original on/off preference and normal
    /// fade timing. Normal application exit, sleep and user-session changes call it.
    public func restore() {
        guard let active = session ?? pendingRecovery else { return }
        session = nil
        pendingRecovery = active
        generation &+= 1
        var issues: [String] = []
        // Restore the original preference even if a previous command failed.
        if active.client.mode != active.originalMode {
            do { try active.client.set(NSNumber(value: active.originalMode), key: "LEBacklightMode") }
            catch { issues.append(error.localizedDescription) }
        }
        if displayAwake {
            // Always attempt the final Unblank, even if the preceding keyboard
            // correction fails. Each cleanup step is independent and best effort.
            do { try active.client.fade(lit: false, duration: 0, keepKeyboardLit: true) }
            catch { issues.append(error.localizedDescription) }
            do { try active.client.fade(lit: true, duration: 0, keepKeyboardLit: true) }
            catch { issues.append(error.localizedDescription) }
        } else {
            // Never send an Unblank or keyboard correction during real sleep.
            do { try active.client.fade(lit: false, duration: 0, keepKeyboardLit: false) }
            catch { issues.append(error.localizedDescription) }
        }
        // Retry resetting duration independently of any rejected state transition.
        do { try active.client.set(NSNumber(value: 0), key: "LEPWMFactorFadeDuration") }
        catch { issues.append(error.localizedDescription) }
        if active.client.mode != active.originalMode {
            issues.append("The original on/off setting has not been confirmed by macOS.")
        }
        if issues.isEmpty { pendingRecovery = nil }
        lastRestoreIssue = issues.isEmpty ? nil : issues.joined(separator: " ")
    }

    private func beginSession() throws -> Session {
        restore()
        guard pendingRecovery == nil else {
            throw HardwareControlError.unavailable(
                "The previous logo state could not be restored. Control remains stopped; retry stopping control before starting another effect."
            )
        }
        refresh()
        guard report.logoDetected else { throw HardwareControlError.unavailable(report.summary) }
        if let competitor = competingApplications().first {
            throw HardwareControlError.competingApplication(competitor)
        }
        guard report.directControlAvailable,
              let client = CoreBrightnessClient(),
              let originalMode = client.mode, [0, 2].contains(originalMode) else {
            throw HardwareControlError.unavailable("The logo interface is unavailable. Use the on-screen preview.")
        }
        guard displayAwake else {
            throw HardwareControlError.unavailable("Wake the display before starting a logo effect.")
        }
        generation &+= 1
        let active = Session(client: client, originalMode: originalMode, generation: generation)
        session = active
        return active
    }

    private func check(_ active: Session) throws {
        try Task.checkCancellation()
        guard session?.generation == active.generation, displayAwake else { throw CancellationError() }
        guard active.client.factor != nil else {
            throw HardwareControlError.commandRejected("LEPWMState")
        }
    }

    private func fade(_ lit: Bool, duration: Double, session active: Session) async throws {
        try check(active)
        try active.client.fade(lit: lit, duration: duration, keepKeyboardLit: true)
        try await wait(duration, session: active)
    }

    private func wait(_ seconds: Double, session active: Session) async throws {
        try check(active)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try check(active)
    }

    private func competingApplications() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            let name = app.localizedName ?? ""
            let lowerName = name.lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()
            let knownNames = ["logolight", "backglow", "codeman", "codeman-desktop"]
            if knownNames.contains(lowerName) || bundle == "app.logolight.logolight" || bundle.hasPrefix("app.backglow.") {
                return name.isEmpty ? "another logo utility" : name
            }
            return nil
        }.sorted()
    }

    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willPowerOffNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displayAwake = false
                    self?.restore()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
                    // An effect never restarts itself after wake. The application must
                    // explicitly request a new session if the user still enabled it.
                }
            })
        }
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        })
    }
}
