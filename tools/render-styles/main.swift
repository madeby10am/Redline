// Renders every menu bar style in light and dark mode to a PNG, for the README.
// Usage: swiftc Sources/Gauges.swift tools/render-styles/main.swift -o build/render && build/render docs/menu-bar-styles.png
import AppKit

let readings: [Reading] = [
    Reading(letter: "C", text: "34%", widestText: "100%", fraction: 0.34, health: .cpu(0.34)),
    Reading(letter: "R", text: "86%", widestText: "100%", fraction: 0.86, health: .memory(0.86)),
    Reading(letter: "T", text: "82°", widestText: "100°", fraction: 82 / 105, health: .temperature(82)),
]
let history: [Double] = [0.12, 0.15, 0.1, 0.22, 0.35, 0.6, 0.55, 0.4, 0.3, 0.28, 0.45, 0.7, 0.52, 0.33, 0.25, 0.3, 0.38, 0.34]

let scale: CGFloat = 4, columnWidth = 700, rowHeight: CGFloat = 22 * scale + 16
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: columnWidth * 2,
                           pixelsHigh: Int(rowHeight * CGFloat(BarStyle.allCases.count)) + 16,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

for (row, style) in BarStyle.allCases.enumerated() {
    for (column, dark) in [false, true].enumerated() {
        let y = CGFloat(rep.pixelsHigh) - rowHeight * CGFloat(row + 1)
        let x = CGFloat(column * columnWidth)
        (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
        NSRect(x: x, y: y, width: CGFloat(columnWidth), height: rowHeight).fill()
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let image = MenuBarIcon.image(style: style, readings: readings, cpuHistory: history)
            image.draw(in: NSRect(x: x + 16, y: y + 8, width: image.size.width * scale, height: 22 * scale))
        }
    }
}

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
