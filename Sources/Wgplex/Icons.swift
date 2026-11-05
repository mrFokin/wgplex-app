import AppKit
import WgplexKit

/// Template shield icons drawn in code (no assets).
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func image(for icon: MenuIcon) -> NSImage {
        let key = "\(icon)"
        if let image = cache[key] { return image }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(icon)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    private static func shield() -> NSBezierPath {
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

    private static func draw(_ icon: MenuIcon) {
        let path = shield()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        if icon == .on {
            path.fill()
            return
        }
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.stroke()
        switch icon {
        case .warn, .unavailable:
            NSBezierPath(rect: NSRect(x: 8.25, y: 7, width: 1.5, height: 5.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 8.2, y: 4.6, width: 1.6, height: 1.6)).fill()
        case .paused:
            NSBezierPath(rect: NSRect(x: 6.6, y: 5.5, width: 1.7, height: 6.5)).fill()
            NSBezierPath(rect: NSRect(x: 9.7, y: 5.5, width: 1.7, height: 6.5)).fill()
        case .off, .on:
            break
        }
    }
}
