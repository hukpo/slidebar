import AppKit

/// The built-in keyboard backlight, through CoreBrightness's KeyboardBrightnessClient (private).
/// Every call is guarded: if the class or a method is missing, the feature simply isn't offered.
enum KeyboardBacklight {
    private typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias IDs = @convention(c) (AnyObject, Selector) -> NSArray?

    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        return cls.init()
    }()

    private static func imp<T>(_ name: String, as type: T.Type) -> T? {
        guard let client, client.responds(to: NSSelectorFromString(name)) else { return nil }
        return unsafeBitCast(client.method(for: NSSelectorFromString(name)), to: type)
    }

    private static var keyboardID: UInt64? {
        guard let client, let ids = imp("copyKeyboardBacklightIDs", as: IDs.self)?(client, NSSelectorFromString("copyKeyboardBacklightIDs")),
              let first = ids.firstObject as? NSNumber
        else { return nil }
        return first.uint64Value
    }

    static var isAvailable: Bool {
        keyboardID != nil
            && imp("brightnessForKeyboard:", as: Get.self) != nil
            && imp("setBrightness:forKeyboard:", as: Set.self) != nil
    }

    /// Backlight level from 0 to 1, or nil when there's no backlit keyboard.
    static func level() -> Float? {
        guard let client, let id = keyboardID, let get = imp("brightnessForKeyboard:", as: Get.self) else { return nil }
        return get(client, NSSelectorFromString("brightnessForKeyboard:"), id)
    }

    @discardableResult
    static func setLevel(_ value: Float) -> Bool {
        guard let client, let id = keyboardID, let set = imp("setBrightness:forKeyboard:", as: Set.self) else { return false }
        return set(client, NSSelectorFromString("setBrightness:forKeyboard:"), min(max(value, 0), 1), id)
    }
}
