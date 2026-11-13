import AppKit
import Foundation

// A native drawing keeps the development app self-contained: no remote assets.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Glow.icns")
let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("glow-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

func drawIcon(size: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(srgbRed: 0.19, green: 0.22, blue: 0.26, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1))!.draw(in: tile, angle: -65)

    context.saveGState()
    context.setShadow(offset: .zero, blur: 80, color: NSColor(srgbRed: 1, green: 0.64, blue: 0.18, alpha: 0.8).cgColor)
    NSColor(srgbRed: 1, green: 0.77, blue: 0.34, alpha: 1).setFill()
    let outer = NSBezierPath(ovalIn: NSRect(x: 245, y: 245, width: 534, height: 534))
    outer.fill()
    context.restoreGState()

    // Three softly cut bands read as an accumulating daily charge.
    context.saveGState()
    outer.addClip()
    NSColor(srgbRed: 1, green: 0.94, blue: 0.75, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 235, y: 245, width: 554, height: 145)).fill()
    NSColor(srgbRed: 1, green: 0.85, blue: 0.47, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 235, y: 407, width: 554, height: 146)).fill()
    NSColor(srgbRed: 0.14, green: 0.16, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 235, y: 390, width: 554, height: 17)).fill()
    NSBezierPath(rect: NSRect(x: 235, y: 553, width: 554, height: 17)).fill()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: iconset.appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    try drawIcon(size: base, name: "icon_\(base)x\(base).png")
    try drawIcon(size: base * 2, name: "icon_\(base)x\(base)@2x.png")
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
