import SwiftUI

/// An sRGB colour as 8-bit components. Kept free of SwiftUI so the tokens can be unit tested.
struct StatusRGB: Equatable, Sendable {
    let red: UInt8, green: UInt8, blue: UInt8
}

extension StatusColor {
    /// The fixed colour for this token in the given appearance, or `nil` for `.muted`, which uses
    /// the system secondary colour. Light Mode uses darker caution and error variants so small
    /// text reaches at least 4.5:1 contrast on a white background.
    func rgb(dark: Bool) -> StatusRGB? {
        switch self {
        case .primary: StatusRGB(red: 0x25, green: 0x63, blue: 0xEB)
        case .caution: dark ? StatusRGB(red: 0xEA, green: 0xB3, blue: 0x08) : StatusRGB(red: 0xA1, green: 0x62, blue: 0x07)
        case .error: dark ? StatusRGB(red: 0xEF, green: 0x44, blue: 0x44) : StatusRGB(red: 0xB9, green: 0x1C, blue: 0x1C)
        case .muted: nil
        }
    }

    func swiftUIColor(_ scheme: ColorScheme) -> Color {
        guard let rgb = rgb(dark: scheme == .dark) else { return Color.secondary }
        return Color(red: Double(rgb.red) / 255.0, green: Double(rgb.green) / 255.0, blue: Double(rgb.blue) / 255.0)
    }
}

extension StatusGlyph {
    var systemName: String {
        switch self {
        case .linked: "antenna.radiowaves.left.and.right"
        case .searching: "dot.radiowaves.left.and.right"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .crossedOut: "antenna.radiowaves.left.and.right.slash"
        case .cloudSlash: "xmark.circle"
        case .syncProgress: "arrow.clockwise"
        case .transfer: "arrow.up.arrow.down"
        case .cloudCheck: "checkmark.circle"
        }
    }
}

public struct StatusRowView: View {
    public let state: StatusRowState
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme
    public init(state: StatusRowState) { self.state = state }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                indicator(state.pumpLink.glyph, color: state.pumpLink.color)
                if let text = state.pumpLink.text {
                    Text(text).font(.caption2.weight(.medium)).foregroundStyle(state.pumpLink.color.swiftUIColor(colorScheme))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.pumpLink.accessibilityLabel)
            .accessibilityIdentifier("status.pump-link")
            if let sync = state.sync {
                indicator(sync.glyph, color: sync.color)
                    .accessibilityLabel(sync.accessibilityLabel)
                    .accessibilityIdentifier("status.sync")
            }
            if let reachability = state.reachability {
                HStack(spacing: 4) {
                    indicator(reachability.glyph, color: reachability.color)
                    if let text = reachability.text { Text(text).font(.caption2.weight(.medium)).foregroundStyle(reachability.color.swiftUIColor(colorScheme)) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reachability.accessibilityLabel)
                .accessibilityIdentifier("status.backend")
            }
            if !state.marks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(state.marks) { entry in
                            let mark = entry.mark
                            Image(mark.assetName).renderingMode(.original).resizable().scaledToFit()
                                .frame(height: mark.height)
                                .accessibilityLabel("\(mark.name) plugin active")
                                .accessibilityIdentifier(mark.accessibilityIdentifier)
                        }
                    }
                }
                .layoutPriority(-1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.status-row-slot")
    }

    private func indicator(_ glyph: StatusGlyph, color: StatusColor) -> some View {
        Image(systemName: glyph.systemName).font(.system(size: glyphSize)).foregroundStyle(color.swiftUIColor(colorScheme))
            .frame(width: glyphSize, height: glyphSize)
    }
}
