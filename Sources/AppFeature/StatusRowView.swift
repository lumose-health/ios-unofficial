import SwiftUI

private extension StatusColor {
    var swiftUIColor: Color {
        switch self {
        case .primary: Color(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0)
        case .caution: Color(red: 0xEA / 255.0, green: 0xB3 / 255.0, blue: 0x08 / 255.0)
        case .error: Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0)
        case .muted: Color.secondary
        }
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
    public init(state: StatusRowState) { self.state = state }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                indicator(state.pumpLink.glyph, color: state.pumpLink.color)
                if let text = state.pumpLink.text {
                    Text(text).font(.caption2.weight(.medium)).foregroundStyle(state.pumpLink.color.swiftUIColor)
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
                    if let text = reachability.text { Text(text).font(.caption2.weight(.medium)).foregroundStyle(reachability.color.swiftUIColor) }
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
        Image(systemName: glyph.systemName).font(.system(size: glyphSize)).foregroundStyle(color.swiftUIColor)
            .frame(width: glyphSize, height: glyphSize)
    }
}
