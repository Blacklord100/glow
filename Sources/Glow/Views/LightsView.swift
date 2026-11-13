import SwiftUI

struct LightsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Give your Mac a rhythm.").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Choose a light for the way you work.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(colors: [Color.primary.opacity(0.04), Color.primary.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                        ApplePreview(progress: model.dailyProgress, mode: model.mode, cycle: model.cycleDuration, size: 74)
                    }.frame(height: 205)
                        .overlay(alignment: .bottom) { Capsule().fill(.primary.opacity(0.15)).frame(width: 175, height: 3).offset(y: 5) }
                        .padding(.top, 12)
                    Text("ON-SCREEN PREVIEW").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary)
                    Text(model.mode.detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if model.mode == .dailyCharge {
                        Text("The filling shape is a screen concept. Physical Daily Charge uses milestone pulses.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }.frame(width: 330)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(GlowMode.allCases) { mode in
                        Button { model.mode = mode } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.symbol).frame(width: 20).foregroundStyle(model.mode == mode ? Color.orange : Color.secondary)
                                Text(mode.title).font(.system(size: 13, weight: model.mode == mode ? .medium : .regular))
                                Spacer()
                                if model.mode == mode { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
                            }.padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
                                .background(model.mode == mode ? Color.orange.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                    if model.mode == .breathe || model.mode == .pulse {
                        VStack(spacing: 5) {
                            HStack { Text("Cycle"); Spacer(); Text("\(Int(model.cycleDuration)) seconds").monospacedDigit() }
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Slider(value: $model.cycleDuration, in: 3...12, step: 1) { Text("Cycle duration") }
                                .labelsHidden()
                        }.padding(.horizontal, 14).padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity)
            }
            Divider()
            HardwareToggle(model: model)
            Spacer(minLength: 0)
        }.padding(30)
    }
}

struct HardwareToggle: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Control the physical logo").font(.system(size: 13, weight: .medium))
                    Text(model.hardwareReport.directControlAvailable ? "Experimental · attempts to restore its previous state on stop." : model.hardwareReport.summary)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Control the physical logo", isOn: Binding(get: { model.hardwareEnabled }, set: { model.setHardwareEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).disabled(!model.hardwareReport.directControlAvailable)
            }
            if !model.lightingMessage.isEmpty { Text(model.lightingMessage).font(.caption).foregroundStyle(.red) }
        }
    }
}
