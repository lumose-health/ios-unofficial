import SwiftUI
import SafetyCore

extension HeroColor {
    var swiftUIColor: Color {
        switch self {
        case .green: Color(red: 0x22 / 255.0, green: 0xC5 / 255.0, blue: 0x5E / 255.0)
        case .amber: Color(red: 0xEA / 255.0, green: 0xB3 / 255.0, blue: 0x08 / 255.0)
        case .red: Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0)
        case .secondary: Color.secondary
        }
    }
}

public struct GlucoseHeroView: View {
    public let state: HeroState

    public init(state: HeroState) { self.state = state }

    public var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(state.valueText)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(state.valueColor.swiftUIColor)
                    if let glyph = state.glyph {
                        Text(glyph)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(state.glyphColor.swiftUIColor)
                            .padding(.bottom, 8)
                    }
                }
                Text(state.unitText).font(.system(size: 16))
                if let age = state.ageCaption {
                    HStack(spacing: 6) {
                        Text(age).foregroundStyle(state.ageColor.swiftUIColor)
                        if let badge = state.badge.text {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }.font(.caption)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilityLabel)

            if !state.metrics.isEmpty {
                HStack(spacing: 16) {
                    ForEach(state.metrics, id: \.kind) { metric in
                        VStack(spacing: 2) {
                            Text(metric.kind.rawValue).font(.caption)
                            Text(metric.text).font(.subheadline.weight(.medium))
                            if let badge = metric.badge.text { Text(badge).font(.caption2) }
                        }
                        .foregroundStyle(metric.isDeemphasised ? Color.secondary : Color.primary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(metric.accessibilityLabel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).padding(16)
    }
}
