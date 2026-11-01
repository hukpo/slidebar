import AppKit
import BrimCore
import CBrimPrivate

/// `Brim --selftest`: checks the system hooks Brim relies on, then restores every level it touched.
enum SelfTest {
    /// `Brim --simulate`: drives the real gesture engine with synthetic finger paths and checks
    /// that volume, brightness and mute actually change. Restores every level afterwards.
    static func runSimulationIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--simulate") else { return false }
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func line(_ ok: Bool, _ name: String, _ detail: String) { print("\(ok ? "PASS" : "FAIL")  \(name)  (\(detail))") }
        let engine = EdgeEngine.shared
        let prefs = Prefs.shared
        let savedPaused = prefs.paused, savedModifier = prefs.requireModifier
        let savedEdges = prefs.edges, savedCorners = prefs.corners, savedApps = prefs.cornerApps
        prefs.paused = false; prefs.requireModifier = false
        // Test the shipping layout: brightness left, volume right, songs bottom, mute top-right.
        prefs.edges = [.left: .brightness, .right: .volume, .top: .off, .bottom: .songs]
        prefs.corners = [.topLeft: .off, .topRight: .mute, .bottomLeft: .off, .bottomRight: .off]
        engine.syncConfig()
        var clock = 1000.0
        var nextID: Int32 = 100

        func slide(x: Float, from y0: Float, to y1: Float, size: Float = 0.8) {
            nextID += 1
            for i in 0...30 {
                let y = y0 + (y1 - y0) * Float(i) / 30
                engine.feed([TouchPoint(id: nextID, x: x, y: y, size: size)], time: clock)
                clock += 0.012
                wait(0.012)
            }
            engine.feed([], time: clock); clock += 0.05
            wait(0.5)
        }
        func slideAcross(y: Float, from x0: Float, to x1: Float) {
            nextID += 1
            for i in 0...30 {
                engine.feed([TouchPoint(id: nextID, x: x0 + (x1 - x0) * Float(i) / 30, y: y, size: 0.8)], time: clock)
                clock += 0.012
                wait(0.012)
            }
            engine.feed([], time: clock); clock += 0.05
            wait(0.5)
        }
        func tap(x: Float, y: Float) {
            nextID += 1
            engine.feed([TouchPoint(id: nextID, x: x, y: y)], time: clock); clock += 0.05
            engine.feed([], time: clock); clock += 0.12
        }

        let vol0 = SystemControls.volume() ?? 0.5, muted0 = SystemControls.isMuted()
        let b0 = SystemControls.brightness() ?? 0.5

        // Right edge → volume, with the on-screen glow showing while the finger is down.
        let volUp = vol0 < 0.5
        let savedGlow = prefs.edgeGlow, savedExcluded = prefs.excludedApps
        prefs.edgeGlow = true
        nextID += 1
        var glowSeen = false
        for i in 0...30 {
            let t = Float(i) / 30
            let y: Float = volUp ? 0.2 + 0.4 * t : 0.6 - 0.4 * t
            engine.feed([TouchPoint(id: nextID, x: 0.98, y: y, size: 0.8)], time: clock)
            clock += 0.012
            wait(0.012)
            if i == 20 { glowSeen = NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.frame.width < 40 } }
        }
        engine.feed([], time: clock); clock += 0.05
        wait(0.5)
        let vol1 = SystemControls.volume() ?? vol0
        line(volUp ? vol1 > vol0 + 0.05 : vol1 < vol0 - 0.05, "Right edge slide changes volume", String(format: "%.2f → %.2f", vol0, vol1))
        line(glowSeen, "Edge glow shows while sliding", glowSeen ? "visible" : "not visible")
        wait(1.3)
        let glowGone = !NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.frame.width < 40 }
        line(glowGone, "Edge glow fades after release", glowGone ? "hidden" : "still visible")

        // A palm on the edge → nothing.
        wait(0.4) // let the last volume steps from the previous slide land
        let volPalm = SystemControls.volume() ?? 0
        slide(x: 0.98, from: 0.2, to: 0.6, size: 4)
        let volAfterPalm = SystemControls.volume() ?? 0
        line(abs(volAfterPalm - volPalm) < 0.001, "Palm on the edge is ignored", String(format: "%.3f → %.3f", volPalm, volAfterPalm))

        // A palm that slides along the edge, then a finger lands to move the pointer → volume put back.
        let volPalmStart = SystemControls.volume() ?? 0
        let palmUp = volPalmStart < 0.5
        nextID += 1
        let palmID = nextID
        var palmMoved = false
        for i in 0...20 {
            let t = Float(i) / 20
            let y: Float = palmUp ? 0.2 + 0.25 * t : 0.45 - 0.25 * t
            engine.feed([TouchPoint(id: palmID, x: 0.98, y: y, size: 0.8)], time: clock)
            clock += 0.012
            wait(0.012)
        }
        wait(0.3)
        palmMoved = abs((SystemControls.volume() ?? 0) - volPalmStart) > 0.03
        nextID += 1
        engine.feed([TouchPoint(id: palmID, x: 0.98, y: 0.45, size: 0.8),
                     TouchPoint(id: nextID, x: 0.5, y: 0.5, size: 0.8)], time: clock); clock += 0.012
        engine.feed([TouchPoint(id: nextID, x: 0.52, y: 0.5, size: 0.8)], time: clock); clock += 0.012
        engine.feed([], time: clock); clock += 0.05
        wait(0.5)
        let volRestored = SystemControls.volume() ?? 0
        line(palmMoved && abs(volRestored - volPalmStart) < 0.01, "Palm slide is undone when a finger lands",
             String(format: "%.3f → moved → %.3f", volPalmStart, volRestored))

        // Front app turned off → nothing.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            prefs.excludedApps = [front]
            let volEx = SystemControls.volume() ?? 0
            slide(x: 0.98, from: 0.2, to: 0.6)
            line(abs((SystemControls.volume() ?? 0) - volEx) < 0.001, "Turned off in front app", "\(front): volume unchanged")
            prefs.excludedApps = savedExcluded
        }
        prefs.edgeGlow = savedGlow

        // Left edge → brightness.
        let bUp = b0 < 0.5
        slide(x: 0.02, from: bUp ? 0.2 : 0.6, to: bUp ? 0.6 : 0.2)
        wait(0.5)
        let b1 = SystemControls.brightness() ?? b0
        line(bUp ? b1 > b0 + 0.05 : b1 < b0 - 0.05, "Left edge slide changes brightness", String(format: "%.2f → %.2f", b0, b1))

        // Middle of the trackpad → nothing.
        let volBefore = SystemControls.volume() ?? 0
        slide(x: 0.5, from: 0.2, to: 0.6)
        line(abs((SystemControls.volume() ?? 0) - volBefore) < 0.001, "Middle slide is ignored", "volume unchanged")

        // Double-tap top-right corner → mute toggles.
        let m0 = SystemControls.isMuted()
        tap(x: 0.95, y: 0.95); tap(x: 0.95, y: 0.95)
        wait(0.5)
        let m1 = SystemControls.isMuted()
        line(m1 != m0, "Corner double-tap toggles mute", "\(m0) → \(m1)")

        // Custom layout: top edge set to volume, slid left to right.
        prefs.edges[.top] = .volume
        engine.syncConfig()
        wait(0.3)
        let vTop0 = SystemControls.volume() ?? 0
        let topUp = vTop0 < 0.5
        slideAcross(y: 0.96, from: topUp ? 0.3 : 0.7, to: topUp ? 0.7 : 0.3)
        wait(0.4)
        let vTop1 = SystemControls.volume() ?? vTop0
        line(topUp ? vTop1 > vTop0 + 0.05 : vTop1 < vTop0 - 0.05, "Top edge set to Volume works sideways", String(format: "%.2f → %.2f", vTop0, vTop1))
        prefs.edges[.top] = .off

        // Custom layout: left edge set to keyboard brightness.
        if KeyboardBacklight.isAvailable, let k0 = KeyboardBacklight.level() {
            prefs.edges[.left] = .keyboardBrightness
            engine.syncConfig()
            let kUp = k0 < 0.5
            slide(x: 0.02, from: kUp ? 0.2 : 0.6, to: kUp ? 0.6 : 0.2)
            let k1 = KeyboardBacklight.level() ?? k0
            line(kUp ? k1 > k0 + 0.05 : k1 < k0 - 0.05, "Left edge set to Keyboard Brightness works", String(format: "%.2f → %.2f", k0, k1))
            KeyboardBacklight.setLevel(k0)
            prefs.edges[.left] = .brightness
        }

        // Custom layout: bottom-left corner set to mute (toggles mute back).
        prefs.corners[.bottomLeft] = .mute
        engine.syncConfig()
        let mc0 = SystemControls.isMuted()
        tap(x: 0.05, y: 0.05); tap(x: 0.05, y: 0.05)
        wait(0.5)
        let mc1 = SystemControls.isMuted()
        line(mc1 != mc0, "Bottom-left corner set to Mute works", "\(mc0) → \(mc1)")

        // New sliders: microphone volume and Night Shift warmth.
        if Microphone.hasVolume, let mic0 = Microphone.volume() {
            prefs.edges[.left] = .micVolume
            engine.syncConfig()
            let up = mic0 < 0.5
            slide(x: 0.02, from: up ? 0.2 : 0.6, to: up ? 0.6 : 0.2)
            let mic1 = Microphone.volume() ?? mic0
            line(up ? mic1 > mic0 + 0.05 : mic1 < mic0 - 0.05, "Left edge set to Microphone Volume works", String(format: "%.2f → %.2f", mic0, mic1))
            Microphone.setVolume(mic0)
            prefs.edges[.left] = .brightness
        }
        if NightShift.isAvailable, let ns0 = NightShift.rawStrength() {
            let wasActive = NightShift.isActive
            prefs.edges[.left] = .nightShift
            engine.syncConfig()
            let start = NightShift.level() ?? 0
            let up = start < 0.5
            slide(x: 0.02, from: up ? 0.2 : 0.6, to: up ? 0.6 : 0.2)
            let end = NightShift.level() ?? start
            line(up ? end > start + 0.05 : end < start - 0.05, "Left edge set to Night Shift works", String(format: "%.2f → %.2f", start, end))
            NightShift.restore(active: wasActive, strength: ns0)
            prefs.edges[.left] = .brightness
            let back = abs((NightShift.rawStrength() ?? -1) - ns0) < 0.01 && NightShift.isActive == wasActive
            line(back, "Night Shift put back as it was", String(format: "strength %.2f, active %@", NightShift.rawStrength() ?? -1, NightShift.isActive ? "yes" : "no"))
        }

        // New corners: mute microphone and keep awake (each toggled twice, so nothing changes).
        prefs.corners[.bottomRight] = .muteMicrophone
        engine.syncConfig()
        let micMuted0 = Microphone.isMuted()
        tap(x: 0.95, y: 0.05); tap(x: 0.95, y: 0.05); wait(0.4)
        let micMuted1 = Microphone.isMuted()
        tap(x: 0.95, y: 0.05); tap(x: 0.95, y: 0.05); wait(0.4)
        line(micMuted1 != micMuted0 && Microphone.isMuted() == micMuted0, "Corner set to Mute Microphone toggles it",
             "\(micMuted0) → \(micMuted1) → \(Microphone.isMuted())")

        prefs.corners[.bottomRight] = .keepAwake
        engine.syncConfig()
        func awakeAssertion() -> Bool {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "assertions"]
            let pipe = Pipe(); p.standardOutput = pipe; try? p.run()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
            return out.contains("Brim: Keep Mac Awake")
        }
        tap(x: 0.95, y: 0.05); tap(x: 0.95, y: 0.05); wait(0.4)
        let awakeOn = awakeAssertion() && KeepAwake.isOn
        tap(x: 0.95, y: 0.05); tap(x: 0.95, y: 0.05); wait(0.4)
        let awakeOff = !awakeAssertion() && !KeepAwake.isOn
        line(awakeOn && awakeOff, "Corner set to Keep Mac Awake turns it on and off", "on: \(awakeOn), off again: \(awakeOff)")
        prefs.corners[.bottomRight] = .off

        // Run a Shortcut: Brim can read the user's shortcut list (without running any).
        var shortcutNames: [String]? = nil
        UserShortcuts.list { shortcutNames = $0 }
        for _ in 0..<50 where shortcutNames == nil { wait(0.1) }
        line(shortcutNames != nil, "Can list your Shortcuts", "\(shortcutNames?.count ?? 0) found")

        // Edges and Corners map: arrow keys move in the direction pressed.
        let n = TrackpadMap.neighbor
        let arrowsOK = n(.edge(.bottom), .right) == .corner(.bottomRight)
            && n(.edge(.bottom), .up) == .edge(.top)
            && n(.edge(.left), .right) == .edge(.right)
            && n(.edge(.left), .down) == .corner(.bottomLeft)
            && n(.corner(.topLeft), .left) == nil
            && n(.corner(.topRight), .down) == .edge(.right)
        line(arrowsOK, "Map arrow keys move spatially", arrowsOK ? "all 6 moves correct" : "wrong neighbor")

        // Clicking a spot opens its actions menu; choosing an item changes it.
        do {
            let edgeMenu = SpotMenu.make(for: .edge(.right))
            let volumeItem = edgeMenu.items.first { $0.title == EdgeFunction.volume.title }
            let checkedRight = edgeMenu.items.first { $0.state == .on }?.title
            prefs.edges[.right] = .off
            if let volumeItem, let action = volumeItem.action { _ = (volumeItem.target as AnyObject).perform(action) }
            let edgeOK = prefs.edge(.right) == .volume && checkedRight == EdgeFunction.volume.title
            let cornerMenu = SpotMenu.make(for: .corner(.bottomRight))
            let hasLock = cornerMenu.items.contains { $0.title == CornerFunction.lockScreen.title }
            let hasShortcuts = cornerMenu.items.first { $0.title == CornerFunction.runShortcut.title }?.submenu != nil
            line(edgeOK && hasLock && hasShortcuts, "Spot menus list actions and apply the choice",
                 "\(edgeMenu.items.count) edge items, \(cornerMenu.items.count) corner items")
            prefs.edges = [.left: .brightness, .right: .volume, .top: .off, .bottom: .songs]
            engine.syncConfig()
        }

        // Paused → nothing.
        prefs.paused = true; engine.syncConfig()
        let volPaused = SystemControls.volume() ?? 0
        slide(x: 0.98, from: 0.2, to: 0.6)
        line(abs((SystemControls.volume() ?? 0) - volPaused) < 0.001, "Paused ignores slides", "volume unchanged")

        // Restore everything.
        prefs.paused = savedPaused; prefs.requireModifier = savedModifier
        prefs.edges = savedEdges; prefs.corners = savedCorners; prefs.cornerApps = savedApps
        SystemControls.setVolume(vol0)
        SystemControls.setMuted(muted0)
        SystemControls.setBrightness(b0)
        wait(0.4)
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }

    static var keyCheckRequested: Bool { CommandLine.arguments.contains("--check-keys") }

    /// `open -n -W build/Brim.app --args --check-keys`: opens Brim's own test windows and drives real
    /// edge gestures through the engine to check Undo and Redo, Switch Windows and Switch Tabs.
    /// It runs inside the normally launched app so macOS delivers the keys, and it never presses a
    /// key unless one of Brim's own test windows is in front.
    @MainActor
    static func runKeyCheck() async {
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        func line(_ ok: Bool, _ name: String, _ detail: String) { print("\(ok ? "PASS" : "FAIL")  \(name)  (\(detail))"); fflush(stdout) }

        // A minimal app with the standard Edit and Window menus, which is how real apps answer
        // Command-Z, Shift-Command-Z and Control-Tab.
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = m
            mainMenu.addItem(holder)
            return m
        }
        func item(_ title: String, _ action: String, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        _ = menu("Edit", [item("Undo", "undo:", "z", .command), item("Redo", "redo:", "z", [.command, .shift])])
        let windowMenu = menu("Window", [item("Show Previous Tab", "selectPreviousTab:", "\t", [.control, .shift]),
                                         item("Show Next Tab", "selectNextTab:", "\t", .control)])
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu

        func makeWindow(_ title: String, x: CGFloat) -> NSWindow {
            let w = NSWindow(contentRect: NSRect(x: x, y: 300, width: 320, height: 200),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = title
            w.isReleasedWhenClosed = false
            w.tabbingMode = .preferred
            return w
        }
        func inFront() -> Bool { NSApp.isActive && NSApp.keyWindow?.title.hasPrefix("Brim Check") == true }

        let prefs = Prefs.shared, engine = EdgeEngine.shared
        let saved = prefs.edges, savedPaused = prefs.paused, savedExcluded = prefs.excludedApps
        prefs.paused = false
        prefs.excludedApps = []
        var windows: [NSWindow] = []
        func finish() {
            for w in windows { w.close() }
            prefs.edges = saved; prefs.paused = savedPaused; prefs.excludedApps = savedExcluded
        }
        var clock = 3000.0, nextID: Int32 = 950
        func slide(_ side: EdgeSide, up: Bool, travel: Float = 0.15) async -> Bool {
            guard inFront() else { return false }
            nextID += 1
            let x: Float = side == .left ? 0.02 : 0.98
            for i in 0...24 {
                let t = Float(i) / 24
                let y: Float = up ? 0.25 + travel * t : 0.25 + travel - travel * t
                engine.feed([TouchPoint(id: nextID, x: x, y: y, size: 0.8)], time: clock)
                clock += 0.012; await wait(0.012)
            }
            engine.feed([], time: clock); clock += 0.1
            await wait(0.5)
            return true
        }
        func skipped() { print("SKIP  Another app came to the front, so Brim stopped before pressing more keys"); finish() }

        // Undo and Redo, in a text box.
        let editor = makeWindow("Brim Check: Text", x: 200)
        windows.append(editor)
        editor.tabbingMode = .disallowed
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        text.allowsUndo = true
        editor.contentView = text
        editor.makeKeyAndOrderFront(nil)
        editor.makeFirstResponder(text)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        for _ in 0..<80 where !inFront() { await wait(0.1) }
        guard inFront() else {
            print("SKIP  Brim couldn't come to the front, so no keys were pressed")
            finish(); return
        }
        text.insertText("hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        text.breakUndoCoalescing()
        prefs.edges[.left] = .undo
        engine.syncConfig()
        guard await slide(.left, up: false) else { return skipped() }
        line(text.string.isEmpty, "Undo slide undoes", "\"hello\" → \"\(text.string)\"")
        guard await slide(.left, up: true) else { return skipped() }
        line(text.string == "hello", "Redo slide redoes", "→ \"\(text.string)\"")

        // Switch Windows, between two of Brim's windows.
        let second = makeWindow("Brim Check: Second Window", x: 560)
        windows.append(second)
        second.tabbingMode = .disallowed
        second.orderFront(nil)
        editor.makeKeyAndOrderFront(nil)
        await wait(0.4)
        prefs.edges[.bottom] = .windows
        engine.syncConfig()
        guard inFront() else { return skipped() }
        nextID += 1
        for i in 0...20 {
            engine.feed([TouchPoint(id: nextID, x: 0.3 + 0.4 * Float(i) / 20, y: 0.04, size: 0.8)], time: clock)
            clock += 0.012; await wait(0.012)
        }
        engine.feed([], time: clock); clock += 0.1
        await wait(0.8)
        line(NSApp.keyWindow === second, "Window swipe switches windows", "key window: \(NSApp.keyWindow?.title ?? "none")")

        // Switch Tabs, in a window with two tabs.
        editor.orderOut(nil); second.orderOut(nil)
        let tabA = makeWindow("Brim Check: Tab A", x: 300)
        let tabB = makeWindow("Brim Check: Tab B", x: 300)
        windows += [tabA, tabB]
        tabA.makeKeyAndOrderFront(nil)
        tabA.addTabbedWindow(tabB, ordered: .above)
        tabA.makeKeyAndOrderFront(nil)
        await wait(0.6)
        prefs.edges[.right] = .tabs
        engine.syncConfig()
        let before = NSApp.keyWindow?.title ?? "none"
        guard await slide(.right, up: true) else { return skipped() }
        let after = NSApp.keyWindow?.title ?? "none"
        line(before != after, "Tab slide switches tabs", "\(before) → \(after)")

        finish()
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        func line(_ ok: Bool, _ name: String, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
        }
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

        line(BrimMTAvailable(), "MultitouchSupport loaded")
        let devices = BrimMTStart({ _, _, _, _ in }, nil)
        BrimMTStop()
        line(devices > 0, "Trackpads found", "\(devices)")
        line(Permissions.isTrusted, "Accessibility granted")
        DeviceWatcher.shared.start()
        line(DeviceWatcher.shared.isWatching, "Watching for trackpads being connected")

        let vol0 = SystemControls.volume()
        let muted0 = SystemControls.isMuted()
        line(vol0 != nil, "Read volume", vol0.map { String(format: "%.2f, muted: %@", $0, muted0 ? "yes" : "no") } ?? "")

        let b0 = SystemControls.brightness()
        line(b0 != nil, "Read brightness", b0.map { String(format: "%.2f", $0) } ?? "")

        if Permissions.isTrusted, let vol0 {
            SystemControls.press(vol0 > 0.5 ? .soundDown : .soundUp)
            wait(0.3)
            let volSnapped = SystemControls.volume() ?? vol0
            line(abs(volSnapped - vol0) > 0.001, "Volume key event", String(format: "%.3f → %.3f", vol0, volSnapped))
            // The first press can snap an in-between level onto the step grid; measure a full step after it.
            SystemControls.press(vol0 > 0.5 ? .soundDown : .soundUp)
            wait(0.3)
            let vol1 = SystemControls.volume() ?? volSnapped
            SystemControls.press(vol0 > 0.5 ? .soundUp : .soundDown, fine: true)
            wait(0.3)
            let vol2 = SystemControls.volume() ?? vol1
            line(abs(abs(vol2 - vol1) - abs(vol1 - volSnapped) / 4) < 0.01, "Fine (⇧⌥) quarter step", String(format: "%.3f → %.3f", vol1, vol2))
            SystemControls.setVolume(vol0)
            SystemControls.setMuted(muted0)
        }
        if Permissions.isTrusted, let b0 {
            SystemControls.press(b0 > 0.5 ? .brightnessDown : .brightnessUp)
            wait(0.6)
            let b1 = SystemControls.brightness() ?? b0
            line(abs(b1 - b0) > 0.001, "Brightness key event", String(format: "%.3f → %.3f", b0, b1))
            SystemControls.setBrightness(b0)
            wait(0.4)
            let b2 = SystemControls.brightness() ?? b0
            line(abs(b2 - b0) < 0.01, "Direct brightness set", String(format: "back to %.3f", b2))
        }
        line(BrimHapticActuate(6), "Force Touch actuator")
        print("INFO  Update feed: \(AppConfig.updateFeedURL?.absoluteString ?? "off")")
        print(String(format: "Restored volume %.2f (muted: %@), brightness %.2f",
                     SystemControls.volume() ?? -1, SystemControls.isMuted() ? "yes" : "no", SystemControls.brightness() ?? -1))
        return true
    }
}
