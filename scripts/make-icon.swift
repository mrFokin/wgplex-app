// Generates packaging/AppIcon.icns: white shield (same shape as the menu bar
// icon) on an indigo-to-blue macOS-style rounded square.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

func shield() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 9, y: 16.5))
    p.line(to: NSPoint(x: 15, y: 14.5))
    p.line(to: NSPoint(x: 15, y: 9))
    p.curve(
        to: NSPoint(x: 9, y: 1.5), controlPoint1: NSPoint(x: 15, y: 5),
        controlPoint2: NSPoint(x: 12, y: 2.8))
    p.curve(
        to: NSPoint(x: 3, y: 9), controlPoint1: NSPoint(x: 6, y: 2.8),
        controlPoint2: NSPoint(x: 3, y: 5))
    p.line(to: NSPoint(x: 3, y: 14.5))
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body with transparent margin.
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let tile = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(
        starting: NSColor(red: 0.36, green: 0.34, blue: 0.84, alpha: 1),
        ending: NSColor(red: 0.12, green: 0.45, blue: 0.95, alpha: 1))!
        .draw(in: tile, angle: -90)
    // Shield (18x18 design box) scaled to ~55% of the body, centred.
    let k = body.width * 0.55 / 14
    var t = AffineTransform()
    t.translate(x: body.midX - 9 * k, y: body.midY - 9 * k)
    t.scale(k)
    let sh = shield()
    sh.transform(using: t)
    NSColor.white.setFill()
    sh.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(2)
}
let out = CommandLine.arguments[1]
let dir = NSTemporaryDirectory() + "AppIcon-\(getpid()).iconset"
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir, "-o", out]
try p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(atPath: dir)
exit(p.terminationStatus)
