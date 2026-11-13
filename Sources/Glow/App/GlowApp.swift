import AppKit
import SwiftUI

@main
struct GlowApp: App {
    @NSApplicationDelegateAdaptor(GlowDelegate.self) private var appDelegate
    @ViewState private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Glow", id: "dashboard") {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Focus") {
                Button(model.isRunning ? "Pause focus" : "Start or resume focus") { model.toggleSession() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("End session") { model.endSession() }.disabled(!model.sessionActive)
            }
        }

        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            Image(nsImage: MenuBarGlyph.make(progress: model.dailyProgress, running: model.isRunning))
                .accessibilityLabel("Glow, \(model.percentLabel) of daily goal")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class GlowDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deliberately a menu-bar utility. The dashboard can be closed without quitting.
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--render-previews"), args.indices.contains(index + 1) {
            Task { @MainActor in
                await Task.yield()
                PreviewExporter.run(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
                NSApp.terminate(nil)
            }
        }
        #endif
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
