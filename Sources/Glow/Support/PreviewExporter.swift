#if DEBUG
import AppKit
import SwiftUI

/// A local development harness. It uses transient AppModel data and never enables
/// hardware, registers login items or writes the user's focus history.
@MainActor
enum PreviewExporter {
    static func run(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = AppModel.shared
            var checks: [String] = []
            func check(_ condition: Bool, _ name: String) throws {
                guard condition else { throw NSError(domain: "GlowPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
                checks.append(name)
            }
            try check(model.todaySeconds == 0, "Preview starts with isolated empty history")
            try capture(ContentView(model: model), to: directory, name: "today-empty")
            model.setGoal(minutes: 240)
            model.addTime(minutes: 135)
            try check(abs(model.dailyProgress - 0.5625) < 0.001, "Manual credit updates daily progress")
            model.sessionMinutes = 45
            model.toggleSession()
            try check(model.isRunning && model.session.durationMinutes == 45, "Selected focus duration starts")
            model.toggleSession()
            try check(model.isPaused, "Pause preserves active session")
            model.toggleSession()
            try check(model.isRunning, "Paused session resumes")
            model.toggleSession()
            model.dismissNotice()
            try capture(ContentView(model: model), to: directory, name: "today-progress")
            model.endSession()
            try check(!model.sessionActive, "Finish returns to ready state")
            try capture(ContentView(model: model), to: directory, name: "today-notice")
            model.dismissNotice()
            model.selectedTab = .lights
            model.mode = .breathe
            try capture(ContentView(model: model), to: directory, name: "lights")
            model.mode = .dailyCharge
            try capture(ContentView(model: model), to: directory, name: "lights-daily")
            model.selectedTab = .lab
            try capture(ContentView(model: model), to: directory, name: "logo-lab")
            try capture(MenuPanel(model: model), to: directory, name: "menu-panel")
            try capture(SettingsView(model: model), to: directory, name: "settings")
            model.refreshHardware()
            try check(!model.hardwareEnabled, "Read-only scan leaves hardware disabled")
            try check(model.hardwareReport.details.contains("Individual LEDs: not verified"), "Report does not claim individual LED control")
            try ("PASS: \(checks.count) app checks\n" + checks.joined(separator: "\n") + "\n")
                .write(to: directory.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)
        } catch {
            try? "FAIL: \(error.localizedDescription)\n".write(to: directory.appendingPathComponent("checks.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static func capture<V: View>(_ content: V, to directory: URL, name: String) throws {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "GlowPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render \(name)"])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GlowPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(name)"])
        }
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        window.close()
    }
}
#endif
