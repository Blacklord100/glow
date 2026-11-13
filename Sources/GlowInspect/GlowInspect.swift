import Foundation
import GlowHardware

@main
struct GlowInspect {
    @MainActor static func main() {
        let hardware = LogoHardware()
        print("Glow · read-only hardware report\n")
        print(hardware.report.details)
    }
}
