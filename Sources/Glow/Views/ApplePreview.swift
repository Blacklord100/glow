import SwiftUI

struct ApplePreview: View {
    var progress: Double
    var mode: GlowMode = .dailyCharge
    var cycle: Double = 6
    var size: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || (mode != .breathe && mode != .pulse))) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(3, cycle)) / max(3, cycle)
            let wave = (1 - cos(phase * .pi * 2)) / 2
            let amount = mode == .breathe ? 0.12 + 0.88 * wave : 0.1 + 0.9 * pow(wave, 4)
            let intensity = reduceMotion ? 0.65 : amount
            ZStack {
                Image(systemName: "apple.logo")
                    .font(.system(size: size)).foregroundStyle(.primary.opacity(0.09))
                if mode == .dailyCharge {
                    Rectangle()
                        .fill(LinearGradient(colors: [.orange, .yellow.opacity(0.85)], startPoint: .bottom, endPoint: .top))
                        .frame(height: size * 1.15 * min(1, max(0, progress)))
                        .frame(width: size, height: size * 1.15, alignment: .bottom)
                        .mask(Image(systemName: "apple.logo").font(.system(size: size)))
                } else if mode != .off {
                    Image(systemName: "apple.logo").font(.system(size: size))
                        .foregroundStyle(.orange.opacity(mode == .automatic ? 0.8 : intensity))
                        .shadow(color: .orange.opacity((mode == .automatic ? 0.7 : intensity) * 0.35), radius: 18)
                }
            }
            .frame(width: size * 1.2, height: size * 1.2)
        }
        .accessibilityLabel(mode == .dailyCharge ? "On-screen Apple \(Int(progress * 100)) percent full" : "\(mode.title) on-screen preview")
        .accessibilityHidden(false)
    }
}
