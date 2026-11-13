import Foundation

enum GlowMode: String, Codable, CaseIterable, Identifiable {
    case dailyCharge, breathe, pulse, automatic, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dailyCharge: "Daily charge"
        case .breathe: "Breathe"
        case .pulse: "Pulse"
        case .automatic: "System default"
        case .off: "Off"
        }
    }
    var symbol: String {
        switch self {
        case .dailyCharge: "chart.bar.fill"
        case .breathe: "wind"
        case .pulse: "waveform.path"
        case .automatic: "sun.max"
        case .off: "moon"
        }
    }
    var detail: String {
        switch self {
        case .dailyCharge: "Your day, one focused minute at a time."
        case .breathe: "A slow rhythm for a little more calm."
        case .pulse: "A small heartbeat on the back of your Mac."
        case .automatic: "Return the logo to its previous setting."
        case .off: "A quiet moment. Lights out."
        }
    }
}

enum GlowFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    static func countdown(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
