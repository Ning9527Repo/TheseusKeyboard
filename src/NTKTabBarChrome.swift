// Extracted from TheseusTabBar.swift; Apache-2.0, Vadim Drobinin.
// Only background material. No tab items / selected pill / lens.
import UIKit

internal enum NTKTabBarChrome {
    struct ChromeCurve {
        var knots: [CGFloat]
        var chroma: CGFloat
        var chromaSlope: CGFloat

        func blended(toward other: ChromeCurve, by amount: CGFloat) -> ChromeCurve {
            let t = min(max(amount, 0), 1)
            return ChromeCurve(
                knots: zip(knots, other.knots).map { $0 + ($1 - $0) * t },
                chroma: chroma + (other.chroma - chroma) * t,
                chromaSlope: chromaSlope + (other.chromaSlope - chromaSlope) * t
            )
        }
    }


    static let iOS27ChromeLight = ChromeCurve(knots: [0.5529, 0.5549, 0.5882, 0.6208, 0.6510, 0.6843, 0.7176, 0.7493, 0.7804, 0.8115, 0.8431, 0.8738, 0.9029, 0.9353, 0.9652, 0.9922], chroma: 0.967, chromaSlope: -0.053)
    static let iOS27ChromeDark = ChromeCurve(knots: [0.1843, 0.1880, 0.2500, 0.3076, 0.3618, 0.4135, 0.4593, 0.5034, 0.5431, 0.5806, 0.6132, 0.6424, 0.6686, 0.6904, 0.7113, 0.7255], chroma: 1.326, chromaSlope: -0.452)

    static func material(isDark: Bool, spectrum: CGFloat) -> ChromeCurve {
        var config = TheseusConfiguration()
        config.theme.neutralBodyScale = 1
        config.theme.backdropSaturation = isDark ? chromeChromaDark : 1
        config.theme.backdropGain = isDark ? 1.01 : 1
        func model(_ amount: CGFloat) -> (knots: [CGFloat], chroma: CGFloat) {
            let knots = (0..<16).map { TheseusMaterialModel.bodyValue(CGFloat($0) / 15, configuration: config, isDark: isDark, spectrum: amount, style: .iOS27) }
            return (knots, TheseusMaterialModel.chromaScale(configuration: config, isDark: isDark, spectrum: amount) * config.theme.backdropGain)
        }
        let measured = isDark ? iOS27ChromeDark : iOS27ChromeLight
        let here = model(min(max(spectrum, 0), 1)), base = model(0.5)
        return ChromeCurve(
            knots: zip(measured.knots, zip(here.knots, base.knots)).map { $0 + $1.0 - $1.1 },
            chroma: measured.chroma + here.chroma - base.chroma,
            chromaSlope: measured.chromaSlope
        )
    }

    static let chromeChromaDark: CGFloat = 1.12
}
