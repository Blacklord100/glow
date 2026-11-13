import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.orange.gradient)
                Text("Glow").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.hardwareReport.directControlAvailable ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(model.hardwareLabel).font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())
                SettingsLink { Image(systemName: "gearshape").font(.system(size: 15)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading, 8)
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 24)

            HStack(spacing: 24) {
                ForEach(AppModel.DashboardTab.allCases) { tab in
                    Button { model.selectedTab = tab } label: {
                        VStack(spacing: 10) {
                            Text(tab.rawValue).font(.system(size: 13, weight: model.selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(model.selectedTab == tab ? Color.primary : Color.secondary)
                            Capsule().fill(model.selectedTab == tab ? Color.orange : Color.clear).frame(height: 2)
                        }.fixedSize(horizontal: true, vertical: false)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text(model.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 12)
            }.padding(.horizontal, 30)
            Divider()

            ScrollView {
                switch model.selectedTab {
                case .today: TodayView(model: model)
                case .lights: LightsView(model: model)
                case .lab: LogoLabView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("Your time stays on this Mac.").font(.system(size: 10))
                Spacer()
                Text("GLOW  /  0.1").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5)
            }.foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 13)
        }
        .frame(width: 820, height: 650)
        .background(.regularMaterial)
        .tint(.orange)
    }
}

struct GlowCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(22)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }
}
