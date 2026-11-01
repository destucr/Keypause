// Renders the Keypause app icon: a keycap with a pause glyph on a deep-teal squircle.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    func rr(_ r: CGRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    // Background squircle (Apple grid: 824pt body inside 1024 canvas)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bg = rr(body, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color(0x0B3B46).setFill(); bg.fill()
    ctx.restoreGState()
    NSGradient(starting: color(0x2BB5A6), ending: color(0x0A2E4D))!.draw(in: bg, angle: -60)

    // Keycap base (darker, gives depth)
    let base = CGRect(x: 232, y: 262, width: 560, height: 520)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 36, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    color(0xC9D3DA).setFill(); rr(base, 96).fill()
    ctx.restoreGState()

    // Keycap top face
    let top = CGRect(x: 262, y: 322, width: 500, height: 450)
    NSGradient(starting: color(0xFFFFFF), ending: color(0xE3EAEE))!.draw(in: rr(top, 78), angle: -90)
    color(0xFFFFFF, 0.9).setStroke()
    let rim = rr(top.insetBy(dx: 2, dy: 2), 76); rim.lineWidth = 4; rim.stroke()

    // Pause glyph
    let barW: CGFloat = 70, barH: CGFloat = 220, gap: CGFloat = 56
    let cx = top.midX, cy = top.midY
    NSGradient(starting: color(0x0F5A63), ending: color(0x0A2E4D))!.draw(in: rr(CGRect(x: cx - gap / 2 - barW, y: cy - barH / 2, width: barW, height: barH), 28), angle: -90)
    NSGradient(starting: color(0x0F5A63), ending: color(0x0A2E4D))!.draw(in: rr(CGRect(x: cx + gap / 2, y: cy - barH / 2, width: barW, height: barH), 28), angle: -90)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns")
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
try render(1024).write(to: out.deletingPathExtension().appendingPathExtension("png"))
