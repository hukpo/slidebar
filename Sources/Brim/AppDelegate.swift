import AppKit
import Combine
import SwiftUI

/// App-wide actions the SwiftUI views can trigger.
final class AppActions {
    static let shared = AppActions()
    weak var delegate: AppDelegate?

    var version: String { AppConfig.version }

    /// The icon tile without its margin, for the app's own UI.
    lazy var badgeImage: NSImage = Brand.badge(size: 168)
    /// The full icon (with margin), for the About panel.
    lazy var iconImage: NSImage = Brand.appIcon(size: 512)

    func checkForUpdates() { Task { await Updater.shared.check(userInitiated: true) } }
    func showSetupGuide() { delegate?.showSetupGuide() }
    func showAbout() { delegate?.showAbout() }
    func finishSetup() { delegate?.finishSetup() }

    func openSource() {
        if let url = AppConfig.sourceURL { NSWorkspace.shared.open(url) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var setupWindow: NSWindow?
    private var levelTimer: Timer?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.keyCheckRequested {
            Task { @MainActor in
                await SelfTest.runKeyCheck()
                NSApp.terminate(nil)
            }
            return
        }
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
        // The glyph shows paused, and a dot when a gesture needs Accessibility.
        prefs.$paused.combineLatest(live.$blockedAction)
            .receive(on: RunLoop.main)
            .sink { [weak self] paused, blocked in
                self?.statusItem.button?.image = Brand.menuBarGlyph(paused: paused, attention: blocked != nil)
                self?.statusItem.button?.setAccessibilityTitle(blocked != nil ? "Brim, needs attention" : "Brim")
            }
            .store(in: &cancellables)

        // Popover.
        let hosting = NSHostingController(rootView: MenuView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Trackpad listening, including trackpads connected later.
        EdgeEngine.shared.start()
        DeviceWatcher.shared.start()

        // Remember the last app the user was in, for "Off in …".
        live.lastApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            LiveState.shared.lastApp = app
        }
        live.refreshLevels()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Watch for Accessibility being granted or revoked.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            LiveState.shared.refreshTrust()
        }
        // When access is granted in System Settings, bring the setup guide back so the user sees the tick.
        live.$trusted
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let window = self?.setupWindow, window.isVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            .store(in: &cancellables)

        Updater.shared.startAutomaticChecks()

        // Only first-timers see the guide on launch. Brim works without Accessibility, so a
        // missing permission is shown calmly in the menu, never forced on every launch.
        if !prefs.hasCompletedSetup {
            showSetupGuide()
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
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        LiveState.shared.refreshLevels()
        LiveState.shared.refreshTrust()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Keep the popover above Brim's own setup window, which activation brings forward.
        if let window = popover.contentViewController?.view.window {
            window.level = .popUpMenu
            window.makeKey()
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
        LiveState.shared.showWelcome = false
    }

    // MARK: Windows

    func showSetupGuide() {
        popover.performClose(nil)
        if setupWindow == nil {
            let view = SetupView()
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Brim"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    /// Closing the setup window with its close button counts as finishing it.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === setupWindow, !Prefs.shared.hasCompletedSetup else { return }
        DispatchQueue.main.async { [weak self] in self?.finishSetup() }
    }

    /// Ends onboarding by opening the menu under Brim's icon, so the user sees where Brim lives.
    func finishSetup() {
        Prefs.shared.hasCompletedSetup = true
        if setupWindow?.isVisible == true { setupWindow?.close() }
        LiveState.shared.showWelcome = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.showPopover() }
    }

    func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Trackpad edges as volume and brightness sliders.\nFree and open source.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Brim",
            .applicationIcon: AppActions.shared.iconImage,
            .credits: credits,
        ])
    }
}
