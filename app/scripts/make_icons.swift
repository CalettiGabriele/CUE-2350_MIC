// Renders the logo SVG into an app icon (.icns) using the system SVG renderer.
// usage: swift make_icons.swift <logo.svg> <out-dir>
// Produces <out-dir>/AppIcon.icns: the logo, black, centred on a white rounded square.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    fputs("usage: make_icons.swift <logo.svg> <out-dir>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let iconset = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    // macOS icon grid: the body is ~80% of the canvas with a ~22% corner radius.
    let body = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225).fill()
    // Fit the logo inside the body with a margin, preserving its aspect ratio.
    let box = body.insetBy(dx: body.width * 0.14, dy: body.height * 0.14)
    let aspect = logo.size.width / max(logo.size.height, 1)
    var target = box
    if aspect > 1 {
        target.size.height = box.width / aspect
        target.origin.y = box.midY - target.height / 2
    } else {
        target.size.width = box.height * aspect
        target.origin.x = box.midX - target.width / 2
    }
    logo.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
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
