import AppKit
import Combine
import SwiftUI

/// App-wide actions the SwiftUI views can trigger.
final class AppActions {
    static let shared = AppActions()
    weak var delegate: AppDelegate?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func showLicense() { delegate?.showLicense() }
    func checkForUpdates() { Task { await Updater.shared.check(userInitiated: true) } }

    /// The icon tile without its margin, for the app's own UI.
    lazy var badgeImage: NSImage = Brand.badge(size: 168)
    /// The full icon (with margin), for the About panel.
    lazy var iconImage: NSImage = Brand.appIcon(size: 512)

    func showSetupGuide() { delegate?.showSetupGuide() }
    func showAbout() { delegate?.showAbout() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var setupWindow: NSWindow?
    private var licenseWindow: NSWindow?
    private var levelTimer: Timer?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActions.shared.delegate = self
        let prefs = Prefs.shared
        let live = LiveState.shared
        prefs.applyAppearance()
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.applicationIconImage = Brand.appIcon(size: 512)
        }

        // Menu bar item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Brand.menuBarGlyph(paused: prefs.paused)
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.setAccessibilityTitle("Brim")
        }
        prefs.$paused
            .sink { [weak self] paused in self?.statusItem.button?.image = Brand.menuBarGlyph(paused: paused) }
            .store(in: &cancellables)

        // Popover.
        let hosting = NSHostingController(rootView: MenuView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Trackpad listening.
        EdgeEngine.shared.start()
        live.refreshLevels()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Watch for Accessibility being granted or revoked.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            LiveState.shared.refreshTrust()
        }

        // Updates and licensing.
        Updater.shared.startAutomaticChecks()
        Licensing.shared.$state
            .removeDuplicates()
            .sink { _ in LiveState.shared.objectWillChange.send() }
            .store(in: &cancellables)

        if !prefs.hasCompletedSetup || !live.trusted {
            showSetupGuide()
        } else if Licensing.shared.state == .expired {
            showLicense()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EdgeEngine.shared.stop()
    }

    @objc private func systemDidWake() {
        // Trackpads are re-created after sleep; listen again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            EdgeEngine.shared.restart()
        }
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            LiveState.shared.refreshLevels()
            LiveState.shared.refreshTrust()
            Licensing.shared.evaluate()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Keep the popover above Brim's own windows (setup guide, license), which activation brings forward.
            if let window = popover.contentViewController?.view.window {
                window.level = .popUpMenu
                window.makeKey()
            }
        }
    }

    func popoverDidShow(_ notification: Notification) {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            LiveState.shared.refreshLevels()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: Windows

    func showSetupGuide() {
        popover.performClose(nil)
        if setupWindow == nil {
            let view = SetupView { [weak self] in self?.setupWindow?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Brim Setup"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    func showLicense() {
        popover.performClose(nil)
        Licensing.shared.evaluate()
        if licenseWindow == nil {
            let view = LicenseView { [weak self] in self?.licenseWindow?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Brim License"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            licenseWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        licenseWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Trackpad edges as volume and brightness sliders.\nSlide, tap and swipe your way around.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Brim",
            .applicationIcon: AppActions.shared.iconImage,
            .credits: credits,
        ])
    }
}
