import AppKit

guard CommandLine.arguments.count == 6 else {
    fputs("usage: IconMaker <output.icns> <symbol> <red> <green> <blue>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let symbolName = CommandLine.arguments[2]
let red = CGFloat(Double(CommandLine.arguments[3]) ?? 0.2)
let green = CGFloat(Double(CommandLine.arguments[4]) ?? 0.6)
let blue = CGFloat(Double(CommandLine.arguments[5]) ?? 1.0)
let accent = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
let iconset = output.deletingPathExtension().appendingPathExtension("iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func render(size: Int, destination: URL) throws {
    let dimension = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconMaker", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: dimension, height: dimension)
    NSColor.clear.setFill()
    bounds.fill()

    let inset = dimension * 0.055
    let card = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: dimension * 0.22, yRadius: dimension * 0.22)
    let gradient = NSGradient(colors: [
        accent.blended(withFraction: 0.10, of: .white) ?? accent,
        accent.blended(withFraction: 0.34, of: NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.09, alpha: 1)) ?? accent
    ])!
    gradient.draw(in: card, angle: -55)

    let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: dimension * 0.09, dy: dimension * 0.09), xRadius: dimension * 0.18, yRadius: dimension * 0.18)
    NSColor.white.withAlphaComponent(0.13).setStroke()
    highlight.lineWidth = max(1, dimension * 0.012)
    highlight.stroke()

    if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
       let symbol = base.withSymbolConfiguration(.init(pointSize: dimension * 0.43, weight: .semibold)) {
        let symbolSize = symbol.size
        let target = NSRect(
            x: (dimension - symbolSize.width) / 2,
            y: (dimension - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.96)
    }

    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconMaker", code: 2)
    }
    try png.write(to: destination, options: .atomic)
}

for (name, size) in entries {
    try render(size: size, destination: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
try? FileManager.default.removeItem(at: iconset)

