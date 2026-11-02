import SlidebarCore
import SwiftUI

/// The settings for one edge or corner, shown under the map when you click it: one row per
/// gesture (slide or swipe, and double-tap), each with its own pop-up of choices.
struct SpotEditor: View {
    let spot: MapSpot
    let close: () -> Void
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Text(spot.title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close \(spot.title) settings")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)

            if case .edge(let side) = spot {
                let function = prefs.edge(side)
                EditorRow(icon: "hand.draw", title: "Slide or swipe",
                          help: function == .off ? "Nothing happens when you slide here." : function.detail(on: side)) {
                    PopUpField(icon: function == .off ? nil : function.icon, appID: nil, title: function.shortTitle,
                               accessibilityName: "\(side.title) slide or swipe") {
                        SpotMenu.slideMenu(for: side)
                    }
                }
                RowDivider()
            }

            let tapOn = prefs.tapIsActive(spot)
            let tap = prefs.tap(spot)
            EditorRow(icon: "hand.tap", title: "Double-tap", help: tapDetail) {
                PopUpField(icon: tapOn ? tap.icon : nil,
                           appID: tapOn && tap == .openApp ? prefs.tapApp(spot) : nil,
                           title: tapOn ? prefs.tapTitle(spot) : "Nothing",
                           accessibilityName: "\(spot.title) double-tap") {
                    SpotMenu.tapMenu(for: spot)
                }
            }
        }
    }

    private var tapDetail: String {
        switch spot {
        case .edge: return "Two quick taps in the same spot on the edge. Works alongside the slide."
        case .corner: return "Two quick taps in the corner."
        }
    }
}

/// One gesture: its name and what it does now, with a pop-up to change it.
private struct EditorRow<Control: View>: View {
    let icon: String
    let title: String
    let help: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            FeatureIcon(systemName: icon)
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .help(help)
    }
}

/// A pop-up button in the macOS style that opens one of Slidebar's native menus under itself.
private struct PopUpField: View {
    let icon: String?
    let appID: String?
    let title: String
    let accessibilityName: String
    let makeMenu: () -> NSMenu
    @State private var anchor = MenuAnchor()
    @State private var hovering = false

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            SpotMenu.pop(makeMenu(), under: view)
        } label: {
            HStack(spacing: 5) {
                if let appID {
                    AppIcon(bundleID: appID).frame(width: 14, height: 14)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.13 : 0.08)))
            .background(AnchorView(anchor: anchor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(title)
        .accessibilityHint("Shows the choices")
    }
}
