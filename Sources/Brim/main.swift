import AppKit

let app = NSApplication.shared
if Snapshot.runIfRequested() || SelfTest.runIfRequested() || SelfTest.runSimulationIfRequested() || SelfTest.runDesktopCheckIfRequested() { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon.
app.setActivationPolicy(.accessory)
app.run()
