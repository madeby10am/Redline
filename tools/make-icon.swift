// Draws Redline's app icon (a tachometer) and writes a 1024px PNG.
// Usage: swift make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background tile (Apple's icon grid: 824pt tile, 100pt margin).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
rgb(0x15171C).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(0x2A2E37), ending: rgb(0x0C0D11))!.draw(in: tilePath, angle: -90)

let center = NSPoint(x: 512, y: 470)
let radius: CGFloat = 290
let start: CGFloat = 225, sweep: CGFloat = 270

// Colored dial: green → yellow → orange → red.
let zones: [(from: CGFloat, to: CGFloat, color: NSColor)] = [
    (0.00, 0.50, rgb(0x34C759)),
    (0.50, 0.75, rgb(0xFFCC00)),
    (0.75, 0.90, rgb(0xFF9500)),
    (0.90, 1.00, rgb(0xFF3B30)),
]
for (i, zone) in zones.enumerated() {
    let path = NSBezierPath()
    let gap: CGFloat = i == 0 ? 0 : 2.5
    path.appendArc(withCenter: center, radius: radius, startAngle: start - sweep * zone.from - gap,
                   endAngle: start - sweep * zone.to, clockwise: true)
    path.lineWidth = 64
    path.lineCapStyle = .butt
    zone.color.setStroke()
    path.stroke()
}
// Rounded outer ends only, so the caps don't spill into the next zone.
for (fraction, color) in [(CGFloat(0), zones.first!.color), (CGFloat(1), zones.last!.color)] {
    let angle = (start - sweep * fraction) * .pi / 180
    let end = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: end.x - 32, y: end.y - 32, width: 64, height: 64)).fill()
}

// Tick marks inside the dial.
for i in 0...10 {
    let angle = (start - sweep * CGFloat(i) / 10) * .pi / 180
    let inner = radius - (i % 5 == 0 ? 110 : 85), outer = radius - 52
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
    tick.line(to: NSPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
    tick.lineWidth = i % 5 == 0 ? 14 : 8
    tick.lineCapStyle = .round
    rgb(0xFFFFFF, 0.55).setStroke()
    tick.stroke()
}

// Needle pushing into the red.
let needleAngle = (start - sweep * 0.94) * .pi / 180
let tip = NSPoint(x: center.x + cos(needleAngle) * (radius - 30), y: center.y + sin(needleAngle) * (radius - 30))
let perp = needleAngle + .pi / 2
let needle = NSBezierPath()
needle.move(to: tip)
needle.line(to: NSPoint(x: center.x + cos(perp) * 22, y: center.y + sin(perp) * 22))
needle.line(to: NSPoint(x: center.x - cos(needleAngle) * 50, y: center.y - sin(needleAngle) * 50))
needle.line(to: NSPoint(x: center.x - cos(perp) * 22, y: center.y - sin(perp) * 22))
needle.close()
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = rgb(0xFF3B30, 0.8)
glow.shadowBlurRadius = 30
glow.set()
rgb(0xFF453A).setFill()
needle.fill()
NSGraphicsContext.restoreGraphicsState()

// Hub.
rgb(0xF2F2F7).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88)).fill()
rgb(0x15171C).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)).fill()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
