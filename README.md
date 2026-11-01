<p align="center"><img src="website/img/icon-512.png" width="128" alt="Brim icon"></p>

<h1 align="center">Brim</h1>
<p align="center"><b>Slide the edge.</b> Your Mac trackpad's edges become brightness and volume sliders.</p>

<p align="center">
  <img src="website/img/menu.png" width="300" alt="Brim menu">
  &nbsp;
  <img src="website/img/settings-dark.png" width="300" alt="Brim settings">
</p>

## What it does

| Gesture | Result |
| --- | --- |
| Slide along the **left edge** | Brightness up / down |
| Slide along the **right edge** | Volume up / down |
| **Double-tap** the top-right corner | Mute / unmute |
| **Swipe** along the bottom edge | Next / previous track |
| **Tap** the bottom edge (opt-in) | Play / pause |
| Hold **⇧⌥** while sliding | Quarter steps |

Brim sends the same key events as the keyboard's brightness and volume keys, so you get the normal macOS on-screen display.

**Menu:** live brightness and volume meters (drag them, or adjust with VoiceOver), an on/off switch, "Off in [current app]", and haptic strength (Off / Light / Medium / Strong).

**Settings:** Quick Mute, Media Strip, Tap to Play, Swap Sides, Edge Width, Bottom Quarter Only, Palm Rejection, Only While Holding Fn or Option, Speed, Keep Pointer Still, Smaller Steps with Shift-Option, Edge Glow, Apps Where Brim Is Off, Appearance, Open at Login, automatic updates.

Also: a first-run setup guide, Pause / Resume, rescan after sleep, menu bar only (no Dock icon), palm rejection, an on-screen edge glow, per-app off switch, and updates that download and install themselves.

## Build

Requires Xcode 15+ (Swift 5.9+). Runs on macOS 13 Ventura or later.

```sh
scripts/build.sh            # → build/Brim.app (universal, signed)
scripts/build.sh --dmg      # also build/Brim-1.0.dmg and website/Brim.dmg
scripts/build.sh --install  # also copy to /Applications and launch
swift test                  # gesture recognizer tests
```

Signing uses `$SIGN_IDENTITY`, or the first Apple Development / Developer ID identity in your keychain, or ad-hoc. Use a real identity if you can: macOS ties the Accessibility grant to the signature, so ad-hoc builds need re-granting after every rebuild.

On first launch, allow Brim in **System Settings → Privacy & Security → Accessibility**. Without it, Brim still changes volume and brightness directly, but there's no on-screen display and media keys won't work.

### Open source

Brim is free and open source. Set where the code lives so the app's ⋯ menu and the website can link to it:

```sh
SOURCE_URL=https://github.com/you/brim scripts/build.sh --dmg
```

and set `sourceURL` in `website/config.js`. Pick a license and add a `LICENSE` file before publishing.

### Releasing updates

```sh
WEBSITE_URL=https://your.site VERSION=1.1 NOTES="New thing|Fixed thing" scripts/build.sh --dmg
```

This writes `website/appcast.json` and `website/downloads/Brim-1.1.dmg`. Upload `website/` and every installed copy finds the update within 12 hours. Brim checks the DMG's SHA-256 and that the new app is signed by the same team, swaps itself and relaunches. Set the version, source link and contact email in `website/config.js`.

### Handy flags

```sh
build/Brim.app/Contents/MacOS/Brim --selftest            # checks trackpad, keys, brightness, haptics (restores levels)
build/Brim.app/Contents/MacOS/Brim --snapshot out/ dark  # renders menu, settings and setup screens to PNG
```

## How it works

```
Sources/
  CBrimPrivate/        C shim, loads private frameworks at runtime (dlopen):
                         MultitouchSupport  raw finger positions + Force Touch actuator
                         DisplayServices    read / set built-in display brightness
  BrimCore/            EdgeRecognizer: pure gesture logic (frames in → actions out), unit tested
  Brim/
    EdgeEngine.swift   runs the recognizer on each trackpad frame and performs actions
    SystemControls     media key events, CoreAudio volume/mute, brightness
    Haptics.swift      actuator ticks, falls back to NSHapticFeedbackManager
    Prefs.swift        settings (UserDefaults) + Open at Login (SMAppService)
    Config.swift       build-time settings from Info.plist (AppConfig)
    Updater.swift      update feed check, download, verify, swap and relaunch
    BrandArt.swift     the app icon and menu bar glyph, drawn in code
    Views/             SwiftUI menu, settings page, setup guide
scripts/
  build.sh             build, bundle, sign, DMG, appcast.json
  IconTool/            renders BrandArt's icon to AppIcon.icns
website/               landing page with an interactive trackpad demo, terms, privacy
```

Gestures only start when a single finger **lands** in an edge zone, so moving the pointer into an edge never triggers anything. A slide is cancelled if the finger moves sideways first, or if a second finger lands before it starts (a scroll).

## Name and icon

**Brim**: the edge of something, as in "filled to the brim". The icon is a trackpad on a midnight tile with a warm brightness edge, a cool volume edge, and a glowing fingertip riding the volume edge.
