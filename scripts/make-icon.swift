// Draws Resources/AppIcon.icns: three mixer faders on a rounded tile.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func render(pixels: Int) -> Data {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else { fatalError("bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    // macOS icon grid: the tile is 824 of 1024 points, centred.
    let tile = NSRect(x: size * 0.098, y: size * 0.098, width: size * 0.804, height: size * 0.804)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: color(0x5B6CFF), ending: color(0x2A1F8F))?.draw(in: tilePath, angle: -90)

    // Soft highlight over the top of the tile.
    NSGraphicsContext.current?.saveGraphicsState()
    tilePath.addClip()
    let highlight = NSRect(
        x: tile.minX,
        y: tile.midY + tile.height * 0.08,
        width: tile.width,
        height: tile.height * 0.42
    )
    NSGradient(starting: color(0xFFFFFF, 0), ending: color(0xFFFFFF, 0.18))?.draw(in: highlight, angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let trackWidth = tile.width * 0.075
    let trackHeight = tile.height * 0.56
    let knobWidth = tile.width * 0.2
    let knobHeight = tile.height * 0.1
    let positions: [CGFloat] = [0.7, 0.35, 0.55]
    for (index, position) in positions.enumerated() {
        let centerX = tile.minX + tile.width * (0.26 + 0.24 * CGFloat(index))
        let trackRect = NSRect(
            x: centerX - trackWidth / 2,
            y: tile.midY - trackHeight / 2,
            width: trackWidth,
            height: trackHeight
        )
        color(0xFFFFFF, 0.28).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackWidth / 2, yRadius: trackWidth / 2).fill()

        let knobY = trackRect.minY + trackHeight * position - knobHeight / 2
        let knobRect = NSRect(x: centerX - knobWidth / 2, y: knobY, width: knobWidth, height: knobHeight)
        color(0x000000, 0.22).setFill()
        NSBezierPath(
            roundedRect: knobRect.offsetBy(dx: 0, dy: -size * 0.008),
            xRadius: knobHeight / 2,
            yRadius: knobHeight / 2
        ).fill()
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: knobHeight / 2, yRadius: knobHeight / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

let variants: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, pixels) in variants {
    try render(pixels: pixels).write(to: iconsetURL.appendingPathComponent("icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try render(pixels: 512).write(to: URL(fileURLWithPath: "Resources/AppIcon-preview.png"))
print("Wrote Resources/AppIcon.icns")
