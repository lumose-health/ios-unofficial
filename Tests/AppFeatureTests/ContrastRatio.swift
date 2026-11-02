import Foundation
@testable import AppFeature

/// WCAG 2 contrast ratio between two sRGB colours.
func contrast(_ a: StatusRGB, _ b: StatusRGB) -> Double {
    func luminance(_ value: StatusRGB) -> Double {
        let channels = [value.red, value.green, value.blue].map { component -> Double in
            let c = Double(component) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    let values = [luminance(a), luminance(b)].sorted()
    return (values[1] + 0.05) / (values[0] + 0.05)
}
