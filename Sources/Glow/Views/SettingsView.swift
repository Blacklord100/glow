import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section("Your day") {
                Stepper("Daily goal: \(GlowFormat.duration(Double(model.goalMinutes * 60)))", value: Binding(get: { model.goalMinutes }, set: { model.setGoal(minutes: $0) }), in: 30...720, step: 30)
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Glow in System Settings → General → Login Items." : nil
                    } catch { loginError = error.localizedDescription }
                }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Lighting") {
                HardwareToggle(model: model)
                Text("Physical control starts off each launch. Individual LED control is still under investigation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local by design") {
                Text("Focus sessions and settings are saved on this Mac. Glow does not record your screen, keystrokes, apps or websites.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(12).frame(width: 450, height: 450).tint(.orange)
    }
}
