import AppKit
import BrimCore

/// What an edge of the trackpad does.
enum EdgeFunction: String, CaseIterable, Identifiable {
    case off
    // Sliders
    case brightness, volume, keyboardBrightness, scroll, zoom
    // Swipes
    case songs, desktops, backForward

    var id: String { rawValue }

    var kind: EdgeKind {
        switch self {
        case .off: return .off
        case .brightness, .volume, .keyboardBrightness, .scroll, .zoom: return .slider
        case .songs, .desktops, .backForward: return .swipe
        }
    }

    var title: String {
        switch self {
        case .off: return "Nothing"
        case .brightness: return "Brightness"
        case .volume: return "Volume"
        case .keyboardBrightness: return "Keyboard Brightness"
        case .scroll: return "Scroll"
        case .zoom: return "Zoom"
        case .songs: return "Next or Previous Song"
        case .desktops: return "Switch Desktop"
        case .backForward: return "Back or Forward"
        }
    }

    /// Fits inside the small trackpad map.
    var shortTitle: String {
        switch self {
        case .off: return "Off"
        case .keyboardBrightness: return "Keyboard"
        case .songs: return "Songs"
        case .desktops: return "Desktops"
        case .backForward: return "Back/Forward"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .off: return "minus"
        case .brightness: return "sun.max"
        case .volume: return "speaker.wave.2"
        case .keyboardBrightness: return "keyboard"
        case .scroll: return "arrow.up.arrow.down"
        case .zoom: return "plus.magnifyingglass"
        case .songs: return "forward"
        case .desktops: return "rectangle.split.3x1"
        case .backForward: return "arrow.uturn.backward"
        }
    }

    /// Plain-language description of the gesture on a given edge.
    func detail(on side: EdgeSide) -> String {
        let (up, down) = side.isVertical ? ("up", "down") : ("right", "left")
        let along = side.isVertical ? "up and down" : "left and right"
        switch self {
        case .off: return "This edge works like the rest of the trackpad."
        case .brightness: return "Slide \(along) to change the display brightness."
        case .volume: return "Slide \(along) to change the volume."
        case .keyboardBrightness: return "Slide \(along) to change the keyboard backlight."
        case .scroll: return "Slide \(along) to scroll whatever is under the pointer."
        case .zoom: return "Slide \(up) to zoom in and \(down) to zoom out, in apps that support ⌘+ and ⌘−."
        case .songs: return "Swipe \(up) for the next song and \(down) for the previous one."
        case .desktops: return "Swipe \(up) to move to the next desktop and \(down) for the previous one."
        case .backForward: return "Swipe \(down) to go back and \(up) to go forward, like in Safari."
        }
    }

    /// Has a level Brim can show and haptically stop at.
    var hasLevel: Bool { self == .brightness || self == .volume || self == .keyboardBrightness }

    /// Works only once Accessibility is allowed (it sends key or scroll events).
    var needsAccess: Bool {
        switch self {
        case .scroll, .zoom, .songs, .desktops, .backForward: return true
        default: return false
        }
    }

    /// The choices offered for an edge on this Mac.
    static var available: [EdgeFunction] {
        allCases.filter { $0 != .keyboardBrightness || KeyboardBacklight.isAvailable }
    }
}

/// What a double-tap in a corner of the trackpad does.
enum CornerFunction: String, CaseIterable, Identifiable {
    case off, mute, playPause, nextSong, previousSong
    case missionControl, showDesktop, spotlight, screenshot, lockScreen, sleepDisplay, openApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Nothing"
        case .mute: return "Mute"
        case .playPause: return "Play or Pause"
        case .nextSong: return "Next Song"
        case .previousSong: return "Previous Song"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .spotlight: return "Spotlight"
        case .screenshot: return "Take a Screenshot"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Turn Off Display"
        case .openApp: return "Open an App"
        }
    }

    var icon: String {
        switch self {
        case .off: return "minus"
        case .mute: return "speaker.slash"
        case .playPause: return "playpause"
        case .nextSong: return "forward.end"
        case .previousSong: return "backward.end"
        case .missionControl: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .spotlight: return "magnifyingglass"
        case .screenshot: return "camera.viewfinder"
        case .lockScreen: return "lock"
        case .sleepDisplay: return "display"
        case .openApp: return "app"
        }
    }

    var needsAccess: Bool {
        switch self {
        case .playPause, .nextSong, .previousSong, .showDesktop, .spotlight: return true
        default: return false
        }
    }

    /// Grouped for the menu: sound, system, other.
    static let groups: [[CornerFunction]] = [
        [.off],
        [.mute, .playPause, .nextSong, .previousSong],
        [.missionControl, .showDesktop, .spotlight, .screenshot, .lockScreen, .sleepDisplay],
        [.openApp],
    ]
}

extension EdgeSide {
    var title: String {
        switch self {
        case .left: return "Left Edge"
        case .right: return "Right Edge"
        case .top: return "Top Edge"
        case .bottom: return "Bottom Edge"
        }
    }
}

extension Corner {
    var title: String {
        switch self {
        case .topLeft: return "Top-Left Corner"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }
}
