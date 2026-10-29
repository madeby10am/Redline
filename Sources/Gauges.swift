import AppKit

// MARK: - Health levels

enum Health: CaseIterable {
    case good, busy, heavy, tooHigh

    var color: NSColor {
        switch self {
        case .good: .systemGreen
        case .busy: .systemYellow
        case .heavy: .systemOrange
        case .tooHigh: .systemRed
        }
    }

    var name: String {
        switch self {
        case .good: "Healthy"
        case .busy: "Busy"
        case .heavy: "Heavy"
        case .tooHigh: "Too high"
        }
    }

    private static func level(_ value: Double, _ busy: Double, _ heavy: Double, _ tooHigh: Double) -> Health {
        switch value {
        case ..<busy: .good
        case ..<heavy: .busy
        case ..<tooHigh: .heavy
        default: .tooHigh
        }
    }

    static func cpu(_ fraction: Double) -> Health { level(fraction, 0.50, 0.75, 0.90) }
    // macOS deliberately keeps RAM full, so only the top end is a problem.
    static func memory(_ fraction: Double) -> Health { level(fraction, 0.80, 0.90, 0.96) }
    static func temperature(_ celsius: Double) -> Health { level(celsius, 65, 80, 95) }
    static func fan(_ fraction: Double) -> Health { level(fraction, 0.40, 0.65, 0.85) }
}

// MARK: - Menu bar image

enum BarStyle: String, CaseIterable, Identifiable {
    case dials, bars, stacked, graph

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dials: "Dials"
        case .bars: "Bars"
        case .stacked: "Stacked"
        case .graph: "Graph"
        }
    }
}

struct Reading {
    let letter: String
    let text: String
    /// Widest text this reading can show, so the menu bar doesn't jiggle as numbers change.
    let widestText: String
    let fraction: Double
    let health: Health
}

enum MenuBarIcon {
    private static let height: CGFloat = 22
    private static var track: NSColor { NSColor.labelColor.withAlphaComponent(0.22) }

    static func image(style: BarStyle, readings: [Reading], cpuHistory: [Double]) -> NSImage {
        let width: CGFloat
        let draw: () -> Void
        switch style {
        case .dials:
            width = CGFloat(readings.count) * (21 + 6) - 6
            draw = { drawDials(readings) }
        case .bars:
            width = readings.reduce(0) { $0 + textWidth($1.letter, barLetterFont) + 2 + 6 + 8 } - 8
            draw = { drawBars(readings) }
        case .stacked:
            width = 48
            draw = { drawStacked(readings) }
        case .graph:
            width = graphWidth + readings.reduce(0) { $0 + 6 + 2 + 8 + textWidth($1.widestText, numberFont) }
            draw = { drawGraph(readings, history: cpuHistory) }
        }

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Dials

    private static let dialLetterFont = NSFont.systemFont(ofSize: 10.5, weight: .bold)

    private static func drawDials(_ readings: [Reading]) {
        let dial: CGFloat = 21, ring: CGFloat = 2.6
        for (i, reading) in readings.enumerated() {
            let center = NSPoint(x: CGFloat(i) * (dial + 6) + dial / 2, y: height / 2)
            let radius = dial / 2 - ring / 2 - 0.5
            arc(center: center, radius: radius, fraction: 1, width: ring, color: track)
            if reading.fraction > 0.005 {
                arc(center: center, radius: radius, fraction: reading.fraction, width: ring, color: reading.health.color)
            }
            drawText(reading.letter, dialLetterFont, at: NSPoint(x: center.x, y: center.y + 0.5), centered: true)
        }
    }

    private static func arc(center: NSPoint, radius: CGFloat, fraction: Double, width: CGFloat, color: NSColor) {
        let start: CGFloat = 225, sweep: CGFloat = 270
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start,
                       endAngle: start - sweep * CGFloat(min(max(fraction, 0), 1)), clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    // MARK: Vertical bars

    private static let barLetterFont = NSFont.systemFont(ofSize: 10, weight: .bold)

    private static func drawBars(_ readings: [Reading]) {
        var x: CGFloat = 0
        for reading in readings {
            x += drawText(reading.letter, barLetterFont, at: NSPoint(x: x, y: height / 2)) + 2
            fillBar(NSRect(x: x, y: 2, width: 6, height: 18), fraction: reading.fraction,
                    color: reading.health.color, vertical: true)
            x += 6 + 8
        }
    }

    // MARK: Stacked bars

    private static func drawStacked(_ readings: [Reading]) {
        let font = NSFont.systemFont(ofSize: 6.5, weight: .bold)
        for (i, reading) in readings.prefix(3).enumerated() {
            let y = height - 4 - CGFloat(i) * 7
            drawText(reading.letter, font, at: NSPoint(x: 0, y: y))
            fillBar(NSRect(x: 7, y: y - 2, width: 40, height: 4), fraction: reading.fraction,
                    color: reading.health.color, vertical: false)
        }
    }

    private static func fillBar(_ rect: NSRect, fraction: Double, color: NSColor, vertical: Bool) {
        let radius = min(rect.width, rect.height) / 2
        track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        var filled = rect
        let f = CGFloat(min(max(fraction, 0), 1))
        if vertical { filled.size.height *= f } else { filled.size.width *= f }
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    // MARK: Graph + numbers

    private static let graphWidth: CGFloat = 32
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)

    private static func drawGraph(_ readings: [Reading], history: [Double]) {
        let box = NSRect(x: 0, y: 3, width: graphWidth, height: 16)
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        track.setFill()
        clip.fill()
        clip.addClip()
        if history.count > 1 {
            let step = box.width / CGFloat(history.count - 1)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: box.minX, y: box.minY))
            for (i, value) in history.enumerated() {
                path.line(to: NSPoint(x: box.minX + CGFloat(i) * step,
                                      y: box.minY + box.height * CGFloat(min(max(value, 0), 1))))
            }
            path.line(to: NSPoint(x: box.maxX, y: box.minY))
            path.close()
            (readings.first?.health.color ?? .systemGreen).setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        var x = graphWidth + 6
        for reading in readings {
            reading.health.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: height / 2 - 3, width: 6, height: 6)).fill()
            x += 8
            drawText(reading.text, numberFont, at: NSPoint(x: x, y: height / 2))
            x += textWidth(reading.widestText, numberFont) + 6
        }
    }

    // MARK: Helpers

    private static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Draws text vertically centered on `point.y`; returns its width.
    @discardableResult
    private static func drawText(_ text: String, _ font: NSFont, at point: NSPoint, centered: Bool = false) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = centered ? point.x - size.width / 2 : point.x
        (text as NSString).draw(at: NSPoint(x: x, y: point.y - size.height / 2), withAttributes: attrs)
        return size.width
    }
}
