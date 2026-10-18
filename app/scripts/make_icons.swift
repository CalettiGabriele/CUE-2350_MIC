// Draws the app icon (.icns): a paper tile with the mic's dark dot grille, its LED column
// with one lit LED, and an orange stub, in the "Chapter 8" identity. No input file.
// usage: swift make_icons.swift <out-dir>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: make_icons.swift <out-dir>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let iconset = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // macOS icon grid: the body is ~80% of the canvas with a ~22% corner radius.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tile = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    rgb(0xEDEDE8).setFill()
    tile.fill()
    tile.addClip()

    // Dark grille panel on the upper 58% of the tile (y grows upwards).
    let panel = NSRect(x: body.minX, y: body.minY + body.height * 0.42, width: body.width, height: body.height * 0.58)
    rgb(0x4E4E4B).setFill()
    panel.fill()
    rgb(0x2E2E2C).setFill()
    let columns = 6, rows = 5
    let pitch = body.width * 0.105
    let dot = pitch * 0.62
    let gridX = body.minX + body.width * 0.12
    let gridTop = panel.maxY - body.height * 0.1
    for row in 0..<rows {
        for column in 0..<columns {
            let cx = gridX + CGFloat(column) * pitch
            let cy = gridTop - CGFloat(row) * pitch
            NSBezierPath(ovalIn: NSRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot)).fill()
        }
    }

    // LED column on the right: 4 LEDs, the second one lit (mode "enhanced").
    let colWidth = body.width * 0.1
    let column = NSRect(x: body.maxX - body.width * 0.2, y: panel.minY + body.height * 0.06,
                        width: colWidth, height: panel.height - body.height * 0.14)
    rgb(0x3A3A38).setFill()
    NSBezierPath(roundedRect: column, xRadius: colWidth / 2, yRadius: colWidth / 2).fill()
    let led = colWidth * 0.56
    for i in 0..<4 {
        let cy = column.maxY - colWidth * 0.75 - CGFloat(i) * (column.height - colWidth * 1.5) / 3
        let rect = NSRect(x: column.midX - led / 2, y: cy - led / 2, width: led, height: led)
        if i == 1 {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = rgb(0xF05A28)
            glow.shadowBlurRadius = led * 0.9
            glow.set()
            rgb(0xF05A28).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            rgb(0x5B2B28).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    // 1px-style rule between panel and plate, then the orange stub on the paper plate.
    rgb(0x1A1A1A).setFill()
    NSRect(x: body.minX, y: panel.minY - s * 0.006, width: body.width, height: s * 0.012).fill()
    rgb(0xF05A28).setFill()
    NSRect(x: body.minX + body.width * 0.12, y: body.minY + body.height * 0.17,
           width: body.width * 0.24, height: body.height * 0.05).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
