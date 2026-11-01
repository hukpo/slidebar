import SwiftUI

/// "Brim License" window: shows trial / license state, takes a key, links to checkout.
struct LicenseView: View {
    @ObservedObject var licensing = Licensing.shared
    @State private var key = ""
    @State private var error: String?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AppIconView(size: 64)
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if licensing.isLicensed {
                HStack {
                    Button("Deactivate on This Mac") { licensing.deactivate() }
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
            } else if licensing.state == .free {
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("BRIM-…", text: $key, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    if let error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
                HStack {
                    Button("Lost your key?") { licensing.openLostKey() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Buy Brim…") { licensing.openCheckout() }
                    Button("Activate") {
                        error = licensing.activate(key)
                        if error == nil { key = "" }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var title: String {
        switch licensing.state {
        case .free: return "Brim is free"
        case .trial(let days): return "\(days) day\(days == 1 ? "" : "s") left in your trial"
        case .licensed: return "Thanks for buying Brim"
        case .expired: return "Your trial has ended"
        }
    }

    private var detail: String {
        switch licensing.state {
        case .free: return "This build has every feature unlocked. Enjoy."
        case .trial: return "Every feature works during the trial. Paste your license key below if you have one."
        case .licensed(let owner): return "Licensed to \(owner). Free 1.x updates included."
        case .expired: return "Edge gestures are paused. Buy a license once and keep it forever, or paste your key below."
        }
    }
}
