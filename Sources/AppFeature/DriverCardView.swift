import SwiftUI
import DriverAPI
import DomainCore

struct DriverCardView: View {
    @Environment(HomeModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let card: ContributedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.card.title).font(.headline)
            if model.isDemoDriver(card.driver) {
                Text(DemoDataLabel.text).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(card.card.elements.enumerated()), id: \.offset) { item in
                elementView(item.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("home.driver-card.\(card.driver.rawValue).\(card.card.id)")
    }

    @ViewBuilder private func elementView(_ element: CardElement) -> some View {
        switch element {
        case .label(let text, let style):
            Text(text).font(font(for: style))
        case .statusBadge(let text, let color):
            let foreground = colorValue(color)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func font(for style: CardLabelStyle) -> Font {
        switch style {
        case .title: .headline
        case .subtitle: .subheadline.weight(.semibold)
        case .body: .body
        case .caption: .caption
        }
    }

    private func colorValue(_ color: CardColor) -> Color {
        guard let rgb = color.rgb(dark: colorScheme == .dark) else {
            return color == .standard ? .primary : .secondary
        }
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

extension CardColor {
    /// The fixed colour for this token in the given appearance, or `nil` for `.standard` and
    /// `.muted`, which use the system label colours. Every pair reuses an existing Home colour
    /// and reaches at least 4.5:1 for small text: light against white, dark against the dark
    /// secondary system background. `info` keeps the primary blue in Light Mode and uses a
    /// lighter blue in Dark Mode, where the primary blue falls under 4.5:1.
    func rgb(dark: Bool) -> StatusRGB? {
        switch self {
        case .standard, .muted: nil
        case .warning: StatusColor.caution.rgb(dark: dark)
        case .error: StatusColor.error.rgb(dark: dark)
        case .info: dark ? StatusRGB(red: 0x60, green: 0xA5, blue: 0xFA) : StatusColor.primary.rgb(dark: false)
        case .success: HeroColor.green.ageCaptionRGB(dark: dark)
        }
    }
}
