import AppKit

enum MenuBarGlyph {
    @MainActor static func make(progress: Double, running: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 43, height: 18), flipped: false) { rect in
            NSColor.labelColor.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 1, y: 6, width: 6, height: 6))
            if running { dot.fill() } else { dot.lineWidth = 1.2; dot.stroke() }
            let track = NSRect(x: 12, y: 5, width: 29, height: 8)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
            let amount = min(1, max(0, progress))
            if amount > 0 {
                NSColor.labelColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: 12, y: 5, width: max(2, 29 * amount), height: 8), xRadius: 3, yRadius: 3).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
