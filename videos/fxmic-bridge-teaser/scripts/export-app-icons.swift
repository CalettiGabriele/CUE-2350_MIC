// Exports the icons the island shows in the teaser: the icon macOS draws for each channel's app,
// 256 px PNG. Run from the project folder: swift scripts/export-app-icons.swift assets/app-icons

import AppKit
// The icon macOS shows for each app (the same call the app uses on the island), 256 px PNG.
let apps = ["claude": "/Applications/Claude.app", "codex": "/Applications/ChatGPT.app",
            "vscode": "/Applications/Visual Studio Code.app", "notes": "/System/Applications/Notes.app",
            "terminal": "/System/Applications/Utilities/Terminal.app"]
let out = CommandLine.arguments[1]
for (name, path) in apps {
    let icon = NSWorkspace.shared.icon(forFile: path)
    let size = NSSize(width: 256, height: 256)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    print(name)
}
