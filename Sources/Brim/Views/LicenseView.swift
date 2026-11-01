import SwiftUI

/// "Brim License" window: shows trial / license state, takes a key, links to checkout.
struct LicenseView: View {
    @ObservedObject var licensing = Licensing.shared
    @State private var key = ""
    @State private var error: String?
    @State private var justActivated = false
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if licensing.isLicensed {
                    HStack {
                        Button("Deactivate on This Mac") { licensing.deactivate() }
                        Spacer()
                        Button("Done", action: onClose)
                            .buttonStyle(.borderedProminent)
                            .tint(.brimAccent)
                            .keyboardShortcut(.defaultAction)
                    }
                } else if licensing.state == .free {
                    HStack {
                        Spacer()
                        Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                    }
                } else {
                    keyField
                    HStack(spacing: 8) {
                        Button("Lost your key?") { licensing.openLostKey() }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Buy Brim…") { licensing.openCheckout() }
                        Button("Activate") { activate() }
                            .buttonStyle(.borderedProminent)
                            .tint(.brimAccent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 440)
        .animation(.easeOut(duration: 0.2), value: licensing.state)
        .animation(.easeOut(duration: 0.2), value: error)
    }

    private var header: some View {
        ZStack {
            NightBackground(cornerRadius: 0)
            VStack(spacing: 10) {
                AppIconView(size: 60)
                    .scaleEffect(justActivated ? 1.12 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.5), value: justActivated)
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                chip
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var chip: some View {
        let (text, color): (String, Color) = {
            switch licensing.state {
            case .free: return ("Free edition", .brimCyan)
            case .trial(let days): return ("Trial · \(days) day\(days == 1 ? "" : "s") left", .brimCyan)
            case .licensed: return ("Licensed", .green)
            case .expired: return ("Trial ended", .orange)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.3)))
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("License key")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("BRIM-…", text: $key, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...4)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(error == nil ? Color.primary.opacity(0.1) : Color.red.opacity(0.6))
                )
                .onSubmit(activate)
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func activate() {
        error = licensing.activate(key)
        if error == nil {
            key = ""
            justActivated = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { justActivated = false }
        }
    }

    private var title: String {
        switch licensing.state {
        case .free: return "Brim is free"
        case .trial: return "Enjoying Brim?"
        case .licensed: return "Thanks for buying Brim"
        case .expired: return "Your trial has ended"
        }
    }

    private var detail: String {
        switch licensing.state {
        case .free: return "This build has every feature unlocked. Enjoy."
        case .trial: return "Every feature works during the trial. Buy once and keep it forever, or paste the key from your receipt."
        case .licensed(let owner): return "Licensed to \(owner). All 1.x updates are included."
        case .expired: return "Edge gestures are paused until you add a license. Buy once and keep it forever."
        }
    }
}
