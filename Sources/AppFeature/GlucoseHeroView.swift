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

    func ageCaptionRGB(dark: Bool) -> StatusRGB? {
        if dark {
            switch self {
            case .green: StatusRGB(red: 0x22, green: 0xC5, blue: 0x5E)
            case .amber: StatusRGB(red: 0xEA, green: 0xB3, blue: 0x08)
            case .red: StatusRGB(red: 0xEF, green: 0x44, blue: 0x44)
            case .secondary: nil
            }
        } else {
            switch self {
            case .green: StatusRGB(red: 22, green: 122, blue: 52)
            case .amber: StatusRGB(red: 138, green: 89, blue: 0)
            case .red: StatusRGB(red: 185, green: 28, blue: 28)
            case .secondary: nil
            }
        }
    }
}

public struct GlucoseHeroView: View {
    public let state: HeroState
    private let onRefresh: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(state: HeroState, onRefresh: (() -> Void)? = nil) { self.state = state; self.onRefresh = onRefresh }

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
                        Text(age).foregroundStyle(ageColor)
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
            .modifier(OptionalRefreshAction(action: onRefresh))

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

    private var ageColor: Color {
        guard let rgb = state.ageColor.ageCaptionRGB(dark: colorScheme == .dark) else { return .secondary }
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

private struct OptionalRefreshAction: ViewModifier {
    let action: (() -> Void)?
    @ViewBuilder func body(content: Content) -> some View {
        if let action { content.accessibilityAction(named: "Refresh", action) }
        else { content }
    }
}
