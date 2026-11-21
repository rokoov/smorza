/// The colour an app is known by, from its icon: the most common saturated hue, kept between dark
/// and light enough to read as a slider's fill in both appearances. Nil for grey icons, which keep
/// the system accent.
public enum IconTint {
    public struct Color: Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    private static let hueBuckets = 24
    /// Pixels greyer than this say nothing about the colour.
    private static let minimumSaturation = 0.35
    private static let minimumBrightness = 0.25
    /// The winning hue has to cover at least this share of the icon.
    private static let minimumShare = 0.05
    /// The result stays readable on a light panel and on a dark one.
    private static let brightnessRange = 0.45...0.85
    private static let finalMinimumSaturation = 0.45

    /// `rgba` holds premultiplied RGBA bytes, four per pixel.
    public static func dominant(rgba: [UInt8]) -> Color? {
        var weights = [Double](repeating: 0, count: hueBuckets)
        var sums = [(red: Double, green: Double, blue: Double)](repeating: (0, 0, 0), count: hueBuckets)
        var opaque = 0
        var index = 0
        while index + 3 < rgba.count {
            defer { index += 4 }
            let alpha = Double(rgba[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            opaque += 1
            let red = min(Double(rgba[index]) / 255 / alpha, 1)
            let green = min(Double(rgba[index + 1]) / 255 / alpha, 1)
            let blue = min(Double(rgba[index + 2]) / 255 / alpha, 1)
            let (hue, saturation, brightness) = hsb(red, green, blue)
            guard saturation >= minimumSaturation, brightness >= minimumBrightness else { continue }
            let bucket = min(Int(hue * Double(hueBuckets)), hueBuckets - 1)
            let weight = saturation * brightness
            weights[bucket] += weight
            sums[bucket].red += red * weight
            sums[bucket].green += green * weight
            sums[bucket].blue += blue * weight
        }
        guard opaque > 0, let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
            weights[best] >= Double(opaque) * minimumShare
        else { return nil }
        let total = weights[best]
        let (hue, saturation, brightness) = hsb(
            sums[best].red / total,
            sums[best].green / total,
            sums[best].blue / total
        )
        let clampedBrightness = min(max(brightness, brightnessRange.lowerBound), brightnessRange.upperBound)
        return color(hue: hue, saturation: max(saturation, finalMinimumSaturation), brightness: clampedBrightness)
    }

    static func hsb(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let range = high - low
        guard range > 0 else { return (0, 0, high) }
        var hue: Double
        if high == red {
            hue = (green - blue) / range
        } else if high == green {
            hue = 2 + (blue - red) / range
        } else {
            hue = 4 + (red - green) / range
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, range / high, high)
    }

    static func color(hue: Double, saturation: Double, brightness: Double) -> Color {
        let sector = hue * 6
        let chroma = brightness * saturation
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (red, green, blue) = (chroma, second, 0)
        case 1: (red, green, blue) = (second, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, second)
        case 3: (red, green, blue) = (0, second, chroma)
        case 4: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let lift = brightness - chroma
        return Color(red: red + lift, green: green + lift, blue: blue + lift)
    }
}
