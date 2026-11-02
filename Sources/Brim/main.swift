import AppKit

// Command-line modes (--snapshot, --selftest, --simulate) run and exit; otherwise start the menu bar app.
let app = NSApplication.shared
if Snapshot.runIfRequested() || SelfTest.runIfRequested() || SelfTest.runSimulationIfRequested() { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon.
app.setActivationPolicy(.accessory)
app.run()
