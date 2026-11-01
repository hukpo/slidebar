import AppKit

let app = NSApplication.shared
if Snapshot.runIfRequested() || SelfTest.runIfRequested() { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon.
app.setActivationPolicy(.accessory)
app.run()
