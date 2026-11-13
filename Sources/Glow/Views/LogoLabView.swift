import AppKit
import SwiftUI

struct LogoLabView: View {
    @Bindable var model: AppModel
    @ViewState private var previewProgress = 0.5
    @ViewState private var copied = false
    @ViewState private var showingReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Can the light grow upward?").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Explore the idea. Check what the hardware actually exposes.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                GlowCard {
                    VStack(spacing: 16) {
                        Text("SPATIAL FILL CONCEPT").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                        ApplePreview(progress: previewProgress, size: 114)
                        HStack {
                            Text("Height").font(.system(size: 12))
                            Spacer()
                            Text("\(Int(previewProgress * 100))%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        }
                        Slider(value: $previewProgress, in: 0...1) { Text("Simulated fill height") }
                            .labelsHidden()
                        Text("Simulation only. This slider changes the on-screen Apple, not the LEDs.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }.frame(width: 290)
                VStack(alignment: .leading, spacing: 16) {
                    Text("HARDWARE CHECK").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    statusRow("This Mac", value: model.hardwareReport.modelIdentifier)
                    statusRow("Logo controller", value: model.hardwareReport.logoDetected ? "Detected" : "Not detected")
                    statusRow("Whole-logo effects", value: model.hardwareReport.directControlAvailable ? "Available to test" : "Unavailable here")
                    statusRow("Individual LEDs", value: "Not established")
                    Divider()
                    Text("Four LEDs do not tell us how many control channels exist. This scan looks for logo and PWM devices without changing them.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button { model.refreshHardware() } label: { Label("Scan hardware", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
                        Button("View report") { showingReport = true }.buttonStyle(.plain).foregroundStyle(.orange)
                    }
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("A rising fill needs two things: separate LED controls, and a visible change in where the light lands. Neither is confirmed yet.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(30)
        .sheet(isPresented: $showingReport) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Read-only hardware report").font(.headline)
                    Spacer()
                    Button(copied ? "Copied" : "Copy report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.hardwareReport.details, forType: .string)
                        copied = true
                    }
                    Button("Done") { showingReport = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(model.hardwareReport.details)
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(width: 680, height: 440)
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }.font(.system(size: 12))
    }
}
