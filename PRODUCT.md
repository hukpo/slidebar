# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The marketing site (`website/`) is static HTML/CSS/JS. The product itself is a native macOS menu bar app (Swift, SwiftUI + AppKit, macOS 13+), so app surfaces follow macOS conventions (Human Interface Guidelines, system accent color, light and dark appearance), not web patterns.

## Users

Everyday Mac users with a MacBook or Magic Trackpad. Not necessarily technical: many have never granted an app Accessibility access and do not know what a "menu bar utility" is. They want to change volume and brightness quickly without hunting for keys, and they expect the app to be obvious, calm and safe to install.

## Product Purpose

Brim turns the edges of the trackpad into sliders: left edge for brightness, right edge for volume, using the same on-screen display as the keyboard keys. Extras: double-tap the top-right corner to mute, swipe the bottom edge to skip tracks, haptic ticks, fine control (⇧⌥ for quarter steps), cursor freeze, palm rejection, an on-screen edge glow, and a list of apps where Brim stays off. Success: a new user installs it, grants permission without confusion, slides once, and never thinks about it again.

## Positioning

Feel and craft. Brim should feel like Apple built it: precise haptics, a quiet native interface, nothing that looks bolted on. Competing apps (e.g. EdgeBar) offer the same basic gesture; Brim wins on how it feels in the hand and how calm and clear it is to set up.

## Operating Context

- Lives in the menu bar only (no Dock icon). The main surface is a popover opened from the menu bar icon; a Settings page and an "apps turned off" page slide in inside the same popover.
- First launch opens a setup window: grant Accessibility, then try a first slide.
- Used in short, frequent glances while doing something else; the popover is opened rarely after setup.

## Capabilities and Constraints

- Requires Accessibility permission to send volume/brightness/media key events; without it Brim still changes levels directly but shows no system on-screen display.
- Reads raw trackpad touches through a private Apple framework; future macOS updates may change behavior.
- Brightness control covers the built-in display only.
- Updates can download and install themselves from an update feed (`appcast.json`) when one is configured.
- **Distribution: free and open source** (confirmed). The current build still contains a 14-day trial, offline license keys and $5 pricing on the website; these conflict with the confirmed model and are pending removal. Open decision: license for the source code, and whether to accept donations.

## Brand Commitments

- Name: **Brim** ("filled to the brim"; the edge of something). Tagline in use: "Slide the edge."
- App icon: a trackpad on a midnight-indigo tile, warm amber brightness edge on the left, cool cyan-violet volume edge on the right, a glowing fingertip on the volume edge. Drawn in code (`Sources/Brim/BrandArt.swift`).
- Brand color (amber → violet → cyan) is reserved for the live level meters and brand moments; app controls use the user's system accent color.

## Evidence on Hand

- Real app screenshots rendered from the app: `website/img/` (menu, settings, light and dark).
- No testimonials, reviews, user counts, press or benchmarks exist. Do not invent any.

## Product Principles

1. Obvious to a first-time Mac user: plain words, one clear next step, no jargon ("Accessibility" is explained, not assumed).
2. Feel first: every interaction should be precise and responsive, with haptics and motion that confirm, never decorate.
3. Native and quiet: follow macOS conventions; color and glow only where they carry meaning (the levels).
4. Never surprising: Brim must not change anything the user did not slide, tap or swipe on purpose.
5. Free and honest: no nags, no fake scarcity, no claims we can't back.
