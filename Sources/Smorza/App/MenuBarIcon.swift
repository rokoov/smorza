import AppKit

/// What the menu bar icon shows: the mixer's sliders, crossed out while Mute All is on, or the
/// output device's volume as a speaker when Settings asks for it.
@MainActor
enum MenuBarIcon {
    private static let symbol = "slider.horizontal.3"
    /// Width of the slash and of the gap cut around it, in points.
    private static let slashWidth: CGFloat = 1.5
    private static let gapWidth: CGFloat = 4

    static func image(isAllMuted: Bool, outputLevel: (volume: Double, isMuted: Bool)?) -> NSImage {
        if isAllMuted {
            return crossedSliders()
        }
        if let outputLevel {
            return speaker(volume: outputLevel.volume, isMuted: outputLevel.isMuted)
        }
        return template(NSImage(systemSymbolName: symbol, accessibilityDescription: "Smorza"))
    }

    /// Low, medium and high like the system's own volume icon.
    private static func speaker(volume: Double, isMuted: Bool) -> NSImage {
        let name =
            switch volume {
            case _ where isMuted: "speaker.slash.fill"
            case ..<0.01: "speaker.fill"
            case ..<0.34: "speaker.wave.1.fill"
            case ..<0.67: "speaker.wave.2.fill"
            default: "speaker.wave.3.fill"
            }
        let percent = Int((volume * 100).rounded())
        let description =
            isMuted ? String(localized: "Smorza, output muted") : String(localized: "Smorza, output at \(percent)%")
        return template(NSImage(systemSymbolName: name, accessibilityDescription: description))
    }

    /// The sliders with a slash through them and a gap cut around it, as the system draws its
    /// slashed symbols; there is no slashed version of this one.
    private static func crossedSliders() -> NSImage {
        guard let sliders = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
            return template(NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil))
        }
        let image = NSImage(size: sliders.size, flipped: false) { rect in
            sliders.draw(in: rect)
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            let start = CGPoint(x: rect.minX + 1, y: rect.maxY - 1)
            let end = CGPoint(x: rect.maxX - 1, y: rect.minY + 1)
            context.setLineCap(.round)
            context.setBlendMode(.destinationOut)
            context.setLineWidth(gapWidth)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            context.setBlendMode(.normal)
            context.setLineWidth(slashWidth)
            context.setStrokeColor(NSColor.black.cgColor)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            return true
        }
        image.accessibilityDescription = String(localized: "Smorza, all apps muted")
        return template(image)
    }

    private static func template(_ image: NSImage?) -> NSImage {
        let image = image ?? NSImage()
        image.isTemplate = true
        return image
    }
}
