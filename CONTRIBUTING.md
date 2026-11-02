# Contributing to Slidebar

Thanks for helping. Slidebar is small on purpose, so the best contributions make it feel better, not bigger.

## Before you start

- **Bugs:** open an issue with your macOS version, Mac or trackpad model, and what you did, expected and saw.
- **Ideas:** open an issue first. Slidebar leaves out anything macOS already does with multi-finger gestures, and every new option has to earn its place.
- **Small fixes** (typos, crashes, clear bugs) can go straight to a pull request.

## Build and test

You need Xcode 15 or later (Swift 5.9+) on macOS 13 Ventura or later.

```sh
swift test                                        # gesture recognizer tests
scripts/build.sh                                  # build/Slidebar.app
build/Slidebar.app/Contents/MacOS/Slidebar --selftest     # trackpad, keys, brightness and haptics checks
build/Slidebar.app/Contents/MacOS/Slidebar --simulate     # drives the gesture engine with fake fingers
build/Slidebar.app/Contents/MacOS/Slidebar --snapshot out/ dark   # renders the screens to PNG
```

`--selftest` and `--simulate` change your real volume and brightness for a moment and put them back.

## Where things live

- `Sources/SlidebarCore`: the gesture recognizer. Pure Swift, no AppKit, fully unit tested. Gesture changes go here, with a test.
- `Sources/Slidebar`: the app (touch input, actions, menu bar UI).
- `Sources/CSlidebarPrivate`: a tiny C shim that loads Apple's private trackpad and display frameworks at runtime.
- `website/`: the static site published to GitHub Pages.

## Style

- Match the code around you: 4-space indents, short doc comments that say *why*.
- UI text is plain and friendly. Write for someone who has never heard of a "menu bar utility".
- Follow macOS conventions: system accent color, light and dark mode, VoiceOver labels, keyboard access.
- Slidebar must never change anything the user didn't slide, tap or swipe on purpose. Accident protection beats features.

## Pull requests

Keep each one focused, describe what changed and how you tested it, and include before and after screenshots for UI changes. By contributing you agree your work is released under the [MIT License](LICENSE).
