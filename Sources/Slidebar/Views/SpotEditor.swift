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

            switch spot {
            case .corner(let corner):
                EditorRow(icon: "hand.tap", title: "Double-tap", help: "Two quick taps in the corner.") {
                    tapField(.corner(corner))
                }
            case .edge(let side):
                EditorRow(icon: "hand.tap", title: "Double-tap",
                          help: "Two quick taps in the same spot on the edge. Works alongside the slide. Split the edge to give each third its own double-tap.") {
                    Picker("Double-tap parts", selection: Binding(
                        get: { prefs.splitEdges.contains(side) },
                        set: { split in
                            if split { prefs.splitEdges.insert(side) } else { prefs.splitEdges.remove(side) }
                        })) {
                        Text("Whole").tag(false)
                        Text("3 parts").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                if prefs.splitEdges.contains(side) {
                    // The three parts side by side, like the edge itself.
                    HStack(spacing: 6) {
                        ForEach(prefs.tapSpots(on: side), id: \.self) { tapSpot in
                            PartTile(label: partTitle(tapSpot), spot: tapSpot)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                } else {
                    PartRow(title: "Whole edge") { tapField(.edge(side, nil)) }
                        .padding(.bottom, 2)
                }
            }
        }
    }

    private func partTitle(_ spot: TapSpot) -> String {
        if case .edge(let side, let section?) = spot { return section.title(on: side) }
        return "Whole edge"
    }

    /// The pop-up showing a double-tap's action, opening its choices.
    private func tapField(_ tapSpot: TapSpot) -> some View {
        let on = prefs.tapIsActive(tapSpot)
        let tap = prefs.tap(tapSpot)
        return PopUpField(icon: on ? tap.icon : nil,
                          appID: on && tap == .openApp ? prefs.tapApp(tapSpot) : nil,
                          title: on ? prefs.tapTitle(tapSpot) : "Nothing",
                          accessibilityName: "\(tapSpot.title) double-tap") {
            SpotMenu.tapMenu(for: tapSpot)
        }
    }
}

/// One part of an edge's double-tap (the whole edge, or a third of it), indented under its row.
private struct PartRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.leading, 44)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
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

/// One third of a split edge: its place on the edge, and what a double-tap there does (or a faint
/// plus when nothing). Click it to choose.
private struct PartTile: View {
    let label: String
    let spot: TapSpot
    @ObservedObject var prefs = Prefs.shared
    @State private var anchor = MenuAnchor()
    @State private var hovering = false

    var body: some View {
        let on = prefs.tapIsActive(spot)
        let tap = prefs.tap(spot)
        Button {
            guard let view = anchor.view else { return }
            SpotMenu.pop(SpotMenu.tapMenu(for: spot), under: view)
        } label: {
            VStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Group {
                    if on, tap == .openApp, let id = prefs.tapApp(spot) {
                        AppIcon(bundleID: id).frame(width: 22, height: 22)
                    } else if on {
                        Image(systemName: tap.icon).font(.system(size: 15))
                    } else {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 22)
                Text(on ? prefs.tapShortTitle(spot) : "Add")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? .primary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.12 : (on ? 0.08 : 0.04))))
            .background(AnchorView(anchor: anchor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(spot.title) double-tap")
        .accessibilityValue(on ? prefs.tapTitle(spot) : "Nothing")
        .accessibilityHint("Shows the choices")
    }
}
