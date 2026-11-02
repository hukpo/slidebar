import Foundation
import IOKit

/// Restarts trackpad listening when a trackpad is connected or disconnected (e.g. a Magic Trackpad).
final class DeviceWatcher {
    static let shared = DeviceWatcher()

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pending: DispatchWorkItem?

    /// True once both "connected" and "disconnected" notifications are registered.
    var isWatching: Bool { iterators.count == 2 }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    guard let context else { return }
                    let watcher = Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue()
                    DeviceWatcher.drain(iterator)
                    watcher.scheduleRestart()
                },
                context, &iterator)
            guard result == KERN_SUCCESS else { continue }
            // Arm the notification by draining the devices that already exist.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }

    /// Devices come and go in bursts; wait for things to settle before re-listening.
    private func scheduleRestart() {
        pending?.cancel()
        let work = DispatchWorkItem {
            NSLog("Slidebar: trackpads changed, listening again")
            EdgeEngine.shared.restart()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
