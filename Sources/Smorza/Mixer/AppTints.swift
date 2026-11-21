import AppKit
import MixerCore
import SwiftUI

/// Each app's colour, read once from its icon and kept, for "Tint sliders with app colour".
@MainActor
final class AppTints {
    /// Icons are read at this size: enough for the colour, cheap to scan.
    private static let side = 32

    private var cache: [String: Color?] = [:]

    func tint(for key: String, icon: NSImage) -> Color? {
        if let cached = cache[key] { return cached }
        let tint = Self.dominantColor(of: icon).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        cache[key] = tint
        return tint
    }

    private static func dominantColor(of icon: NSImage) -> IconTint.Color? {
        guard let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let isDrawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return isDrawn ? IconTint.dominant(rgba: pixels) : nil
    }
}
