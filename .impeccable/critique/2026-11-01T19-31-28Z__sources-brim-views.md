---
target: Brim macOS app UI
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
target_identity: "file:/Users/hukpo/Projects/Brim/Sources/Brim/Views"
timestamp: 2026-11-01T19-31-28Z
slug: sources-brim-views
---
# Critique: Brim macOS app UI (Sources/Brim/Views)

Method: design review only (detector not applicable, native platform)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | Live meters + self-ticking setup; "No Trackpad"/"Needs Access" unexplained; sticky up-to-date banner |
| 2 | Match System / Real World | 2 | Jargon: Media Strip, Edge Width 5%, quarter steps, Require Fn or ⌥, Rescan Trackpads |
| 3 | User Control and Freedom | 2 | Pause buried in ⋯; Skip for Now is default action; update banner not dismissible; trial expiry stops gestures |
| 4 | Consistency and Standards | 2 | Custom switch/segmented/slider; power glyph = Quit and Open at Login; Media Strip row behaves differently; no ⌘, |
| 5 | Error Prevention | 2 | "Open Settings…" fires system prompt + System Settings at once; one-click Quit next to ⋯ |
| 6 | Recognition Rather Than Recall | 3 | Subtitles describe gestures; modifier combos must be remembered |
| 7 | Flexibility and Efficiency | 2 | No keyboard path; no ⌘, / Esc back; smart "Turn Off in ⟨app⟩" |
| 8 | Aesthetic and Minimalist Design | 3 | Calm, brand color disciplined; equal-weight rows, redundant icon tint |
| 9 | Error Recovery | 2 | Raw update error strings; expired trial is punitive; no help when permission isn't detected |
| 10 | Help and Documentation | 2 | Setup guide reopenable; nothing explains Accessibility safety; no source/help link |
| **Total** | | **23/40** | **Acceptable** |

## Design Specificity Verdict
Half authored. EdgeMeters (live levels on the physical edges, swap-aware, mute dimming, draggable) and the setup TrackpadDemo are product-specific. The grouped-card settings grammar below is category-interchangeable, and hand-drawn BrimSwitch/PillPicker/BrimSlider undercut "feels like Apple built it" by losing keyboard focus and VoiceOver semantics.
Deterministic scan: not applicable (native platform).

## What's Working
1. EdgeMeters as status + gesture teacher.
2. Live, self-completing setup checklist (trusted, slideCount), swap-aware copy.
3. Honest microcopy and disciplined color (system accent for controls, brand on meters/glow/headers).

## Priority Issues
- [P0] Trial/license/Buy UI contradicts free+OSS and can disable gestures: Licensing.expired gate, StatusPill .trialEnded, NoticeBanners trial cases, MoreMenu Enter License/Buy, SettingsView licenseLine "Trial · 14 days left", LicenseView, AppDelegate opens License window when expired. Fix: remove licensing; footer "Brim 1.0 · Free and open source"; ⋯ "View Source on GitHub…". Command: distill.
- [P1] Permission step lacks reassurance and collides dialogs; setup reopens every launch while untrusted; orange "Needs Access" for an optional permission; no end-of-onboarding pointer to the menu bar. Fix: single action, reassurance copy, bring window forward on grant, Allow as default, reopen only if setup not completed, neutral "Limited" status, "Brim lives up here" callout. Command: onboard.
- [P1] Custom controls not keyboard/VoiceOver complete (onTapGesture switches, PillPicker segments, LevelBar without adjustable action, unlabeled slider); TrackpadDemo repeatForever ignores Reduce Motion. Fix: native Toggle/Picker/Slider or accessibilityRepresentation + focusable; adjustable actions; gate motion. Command: harden.
- [P2] IA vs frequency: set-once tuning on main page, quick actions (Pause, Turn Off in app) buried; gesture options split across pages; Settings ~750pt with no ScrollView. Fix: main = meters + Pause/Turn Off + Haptics; Settings regrouped (Gestures / Edge Area / While Sliding / General) in a ScrollView; ⌘, and Esc. Command: layout.
- [P3] Jargon and symbol leaks (Edge Width %, ⇧⌥ quarter steps, Rescan Trackpads, Turned Off In, "light tick" when Strong); power icon reuse; accent-tinted icons duplicate switch state. Command: clarify, quieter.

## Persona Red Flags
- Jordan: dual system surfaces at permission; app vanishes after Done; orange "Needs Access" reads as broken; tiny Media Strip chevron.
- Sam: switches, haptic segments, meters unreachable by Tab; low-contrast 9pt chevrons, 10pt footer, % on night card; endless demo with Reduce Motion.
- Maria (everyday user told "it's free"): trial/Buy feels misleading; scary system alert unannounced; glow + system OSD = two indicators; Quick Mute stays top-right after Swap Sides.

## Minor Observations
- Ready status pill is a no-op button; update banners lack dismiss; Quit 2pt from ⋯; mixed filled/outline icons; empty Turned Off In list should host "Add ⟨current app⟩"; Skip for Now is borderedProminent default.

## Questions to Consider
- Should the popover be just meters + Pause, with a real ⌘, Settings window?
- What does the custom switch buy that's worth losing keyboard/VoiceOver?
- Should Accessibility be an optional upgrade, not step 1?
