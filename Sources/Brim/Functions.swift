import AppKit
import BrimCore
import SwiftUI

/// What an edge of the trackpad does. Only things a plain trackpad can't already do with its own
/// multi-finger gestures (so no scrolling, zooming, desktop switching or back/forward here).
enum EdgeFunction: String, CaseIterable, Identifiable {
    case off
    // Sliders with a level
    case brightness, volume, keyboardBrightness, micVolume, nightShift
    // Sliders that step through things
    case tabs, undo
    // Swipes
    case songs, windows

    var id: String { rawValue }

    var kind: EdgeKind {
        switch self {
        case .off: return .off
        case .brightness, .volume, .keyboardBrightness, .micVolume, .nightShift, .tabs, .undo: return .slider
        case .songs, .windows: return .swipe
        }
    }

    var title: String {
        switch self {
        case .off: return "Nothing"
        case .brightness: return "Brightness"
        case .volume: return "Volume"
        case .keyboardBrightness: return "Keyboard Brightness"
        case .micVolume: return "Microphone Volume"
        case .nightShift: return "Night Shift Warmth"
        case .tabs: return "Switch Tabs"
        case .undo: return "Undo and Redo"
        case .songs: return "Next or Previous Song"
        case .windows: return "Switch Windows"
        }
    }

    /// Fits inside the small trackpad map and the meters.
    var shortTitle: String {
        switch self {
        case .off: return "Nothing"
        case .keyboardBrightness: return "Keyboard"
        case .micVolume: return "Microphone"
        case .nightShift: return "Night Shift"
        case .tabs: return "Tabs"
        case .undo: return "Undo"
        case .songs: return "Songs"
        case .windows: return "Windows"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .off: return "minus"
        case .brightness: return "sun.max"
        case .volume: return "speaker.wave.2"
        case .keyboardBrightness: return "keyboard"
        case .micVolume: return "mic"
        case .nightShift: return "moon"
        case .tabs: return "square.on.square"
        case .undo: return "arrow.uturn.backward"
        case .songs: return "forward"
        case .windows: return "macwindow.on.rectangle"
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
        case .micVolume: return "Slide \(along) to change how loud your microphone is, for calls and recordings."
        case .nightShift: return "Slide \(up) for warmer colors and \(down) for cooler ones. Turns Night Shift on."
        case .tabs: return "Slide \(up) for the next tab and \(down) for the previous one, in Safari, Chrome, Finder and most apps with tabs."
        case .undo: return "Slide \(down) to undo and \(up) to redo, one change at a time."
        case .songs: return "Swipe \(up) for the next song and \(down) for the previous one."
        case .windows: return "Swipe \(up) for the app's next window and \(down) for the previous one."
        }
    }

    /// Has a level Brim can show and haptically stop at.
    var hasLevel: Bool {
        switch self {
        case .brightness, .volume, .keyboardBrightness, .micVolume, .nightShift: return true
        default: return false
        }
    }

    /// Slider steps per action, so stepping through tabs or undo history isn't too twitchy.
    var stepsPerAction: Int { (self == .tabs || self == .undo) ? 3 : 1 }

    /// Works only once Accessibility is allowed (it presses keys).
    var needsAccess: Bool {
        switch self {
        case .tabs, .undo, .songs, .windows: return true
        default: return false
        }
    }

    /// How the action reads in a sentence ("… needs Accessibility").
    var blockedName: String {
        switch self {
        case .tabs: return "Switching tabs"
        case .undo: return "Undo and redo"
        case .songs: return "Skipping songs"
        case .windows: return "Switching windows"
        default: return title
        }
    }

    /// The choices offered for an edge on this Mac.
    static var available: [EdgeFunction] {
        allCases.filter {
            switch $0 {
            case .keyboardBrightness: return KeyboardBacklight.isAvailable
            case .micVolume: return Microphone.hasVolume
            case .nightShift: return NightShift.isAvailable
            default: return true
            }
        }
    }
}

/// What a double-tap in a corner of the trackpad does.
enum CornerFunction: String, CaseIterable, Identifiable {
    case off
    case mute, muteMicrophone, playPause, nextSong, previousSong
    case keepAwake, lockScreen, sleepDisplay, screenshot
    case spotlight, emoji
    case runShortcut, openApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Nothing"
        case .mute: return "Mute Sound"
        case .muteMicrophone: return "Mute Microphone"
        case .playPause: return "Play or Pause"
        case .nextSong: return "Next Song"
        case .previousSong: return "Previous Song"
        case .keepAwake: return "Keep Mac Awake"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Turn Off Display"
        case .screenshot: return "Take a Screenshot"
        case .spotlight: return "Spotlight"
        case .emoji: return "Emoji & Symbols"
        case .runShortcut: return "Run a Shortcut"
        case .openApp: return "Open an App"
        }
    }

    var icon: String {
        switch self {
        case .off: return "minus"
        case .mute: return "speaker.slash"
        case .muteMicrophone: return "mic.slash"
        case .playPause: return "playpause"
        case .nextSong: return "forward.end"
        case .previousSong: return "backward.end"
        case .keepAwake: return "cup.and.saucer"
        case .lockScreen: return "lock"
        case .sleepDisplay: return "display"
        case .screenshot: return "camera.viewfinder"
        case .spotlight: return "magnifyingglass"
        case .emoji: return "face.smiling"
        case .runShortcut: return "square.2.layers.3d"
        case .openApp: return "app"
        }
    }

    var needsAccess: Bool {
        switch self {
        case .playPause, .nextSong, .previousSong, .spotlight, .emoji: return true
        default: return false
        }
    }

    /// How the action reads in a sentence ("… needs Accessibility").
    var blockedName: String {
        switch self {
        case .playPause: return "Play and pause"
        case .nextSong, .previousSong: return "Skipping songs"
        case .spotlight: return "Spotlight"
        case .emoji: return "Emoji & Symbols"
        default: return title
        }
    }

    /// Actions that interrupt you if they happen by accident.
    var isDisruptive: Bool { self == .lockScreen || self == .sleepDisplay }

    /// Grouped for the menu: sound, your Mac, typing, your own.
    static let groups: [[CornerFunction]] = [
        [.off],
        [.mute, .muteMicrophone, .playPause, .nextSong, .previousSong],
        [.keepAwake, .lockScreen, .sleepDisplay, .screenshot],
        [.spotlight, .emoji],
        [.runShortcut, .openApp],
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
    /// "Top-right", for summaries.
    var shortTitle: String {
        switch self {
        case .topLeft: return "Top-left"
        case .topRight: return "Top-right"
        case .bottomLeft: return "Bottom-left"
        case .bottomRight: return "Bottom-right"
        }
    }

    var title: String {
        switch self {
        case .topLeft: return "Top-Left Corner"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }
}
