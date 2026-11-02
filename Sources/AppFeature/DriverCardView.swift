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
                .background(foreground.opacity(CardColor.badgeFillOpacity), in: RoundedRectangle(cornerRadius: 4))
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
    /// Opacity of the badge fill, which is the badge text colour laid over the card background.
    static let badgeFillOpacity = 0.12

    /// The card background each appearance is checked against: white in Light Mode and the dark
    /// secondary system background in Dark Mode.
    static func cardBackgroundRGB(dark: Bool) -> StatusRGB {
        dark ? StatusRGB(red: 0x1C, green: 0x1C, blue: 0x1E) : StatusRGB(red: 0xFF, green: 0xFF, blue: 0xFF)
    }

    /// The fixed badge text colour for this token in the given appearance, or `nil` for
    /// `.standard` and `.muted`, which use the system label colours. Each colour reaches at least
    /// 4.5:1 for small text against its own tinted fill composited over the card background, so
    /// some are a shade darker (Light Mode) or lighter (Dark Mode) than the matching Home colour.
    func rgb(dark: Bool) -> StatusRGB? {
        switch self {
        case .standard, .muted: nil
        case .warning: dark ? StatusColor.caution.rgb(dark: true) : StatusRGB(red: 0x85, green: 0x4D, blue: 0x0E)
        case .error: dark ? StatusRGB(red: 0xF8, green: 0x71, blue: 0x71) : StatusColor.error.rgb(dark: false)
        case .info: dark ? StatusRGB(red: 0x60, green: 0xA5, blue: 0xFA) : StatusRGB(red: 0x1D, green: 0x4E, blue: 0xD8)
        case .success: dark ? HeroColor.green.ageCaptionRGB(dark: true) : StatusRGB(red: 0x16, green: 0x65, blue: 0x34)
        }
    }

    /// The badge fill as it appears on screen: the text colour at `badgeFillOpacity` over the card
    /// background, or `nil` where the text uses a system colour.
    func badgeFillRGB(dark: Bool) -> StatusRGB? {
        guard let text = rgb(dark: dark) else { return nil }
        let background = Self.cardBackgroundRGB(dark: dark)
        func blend(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * Self.badgeFillOpacity + Double(bottom) * (1 - Self.badgeFillOpacity)).rounded())
        }
        return StatusRGB(red: blend(text.red, background.red), green: blend(text.green, background.green),
                         blue: blend(text.blue, background.blue))
    }
}
