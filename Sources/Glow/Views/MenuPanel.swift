import AppKit
import SwiftUI

struct MenuPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label("Glow", systemImage: "sun.max.fill").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text(model.percentLabel).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ApplePreview(progress: model.dailyProgress, size: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(GlowFormat.duration(model.todaySeconds)) of \(GlowFormat.duration(Double(model.goalMinutes * 60)))").font(.system(size: 13, weight: .medium))
                    ProgressView(value: model.dailyProgress).tint(.orange)
                    Text("Today's focus").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isRunning ? "Focusing" : model.isPaused ? "Paused" : "Ready when you are")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(GlowFormat.countdown(model.sessionActive ? model.session.remainingSeconds : Double(model.sessionMinutes * 60)))
                        .font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit()
                }
                Spacer()
                Button { model.toggleSession() } label: {
                    Label(model.isRunning ? "Pause" : model.isPaused ? "Resume" : "Focus", systemImage: model.isRunning ? "pause.fill" : "play.fill")
                }.buttonStyle(.borderedProminent).tint(.orange)
            }
            Picker("Light", selection: $model.mode) {
                ForEach(GlowMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.menu)
            HStack {
                Text(model.hardwareEnabled ? "Physical logo enabled" : model.hardwareLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Glow") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }.buttonStyle(.plain)
                Spacer()
                Button("Quit Glow") { NSApp.terminate(nil) }.buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 310).tint(.orange)
    }
}
