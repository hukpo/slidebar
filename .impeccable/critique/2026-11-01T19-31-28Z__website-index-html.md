---
target: Brim website
total_score: 15
max_score: 32
na_heuristics: 7,10
p0_count: 1
p1_count: 2
target_identity: "file:/Users/hukpo/Projects/Brim/website/index.html"
target_fingerprint: "sha256:50b1d2c9c3aabc17ec5bc6ac58545e081cdeb23edd6bbb0e9fdbf5908124ea6b"
target_path: /Users/hukpo/Projects/Brim/website/index.html
timestamp: 2026-11-01T19-31-28Z
slug: website-index-html
---
# Critique: Brim website (website/index.html + sub-pages)

Method: dual-agent (A: a09975b712053fff2 · B: a4751d87645389ada)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2 | Demo OSD feedback good; Buy buttons dead (#get, empty checkoutURL); hint never returns |
| 2 | Match System / Real World | 2 | Jargon feature names; Accessibility unexplained |
| 3 | User Control and Freedom | 3 | Anchors, theme toggle, demo responsive |
| 4 | Consistency and Standards | 1 | "Download" leads to "Buy"; site vs app label mismatch; paid model contradicts free+OSS |
| 5 | Error Prevention | 1 | No install/Gatekeeper/permission guidance; .dmg offered to phones |
| 6 | Recognition Rather Than Recall | 3 | Labeled demo and real screenshots |
| 7 | Flexibility and Efficiency | n/a | Single-pass Persuade page |
| 8 | Aesthetic and Minimalist Design | 2 | Tidy but redundant overview, 11-card grid, changelog filler |
| 9 | Error Recovery | 1 | No help for "can't be opened"/permission denied; mailto-only lost-key form |
| 10 | Help and Documentation | n/a | Persuade surface |
| **Total** | | **15/32** | **Poor (47%)** |

## Design Specificity Verdict
Mostly category-interchangeable dark SaaS template (centered hero + glow, eyebrow/h2 sections, icon-card grid, pricing card, changelog). The interactive trackpad demo is the one authored element and is below the fold and inert until touched.
Deterministic scan: 20 findings in index.html (sub-pages clean). icon-tile-stack ×12 (agrees with LLM template verdict); low-contrast ×2 on #pad labels/hint (~3.6:1 real, 11px), advisory 4.4:1 on card fine print (real); skipped-heading h2→h4 (real); cramped-padding on #pad (likely false positive: children inset ≥18px); tight-leading ×3 (unconfirmed; no element measured 1.26). No live overlay (no mutable interactive browser).

## What's Working
1. Interactive trackpad demo with real step size, OSD, corner double-tap, strip swipe.
2. Real app screenshots with Light/Dark toggle as honest proof.
3. Plain, calm copy; strong privacy page; no invented social proof.

## Priority Issues
- [P0] Site sells $5 trial-ware; product is free+OSS: nav "Buy", hero "$5 once, with a 14-day free trial", .get card, changelog license line, footer Refunds/Manage activation/Lost key, config.js price/checkoutURL, terms/refund/privacy/manage/lost-key content, screenshot with "Trial · 14 days left", no source link. Fix: delete license pages, "Download for Mac" + "View source", short OSS terms, retake screenshots. Command: clarify, distill.
- [P1] No install path or safety case for first-timers; Accessibility only in fine print; setup-dark.png unused. Fix: 3-step Getting started band; "No tracking. Nothing leaves your Mac. Source on GitHub." near download; Gatekeeper guidance if unnotarized. Command: onboard.
- [P1] Hero CTA goes to #get not the file; demo below fold and inert. Fix: direct .dmg link with version/size; pull demo up; idle ghost-finger animation respecting reduced motion; merge Overview into demo. Command: layout, animate.
- [P2] Pointer-only demo, no focus-visible styles, aria-pressed missing, .rv content invisible without JS, smooth scroll ignores reduced motion, low-contrast pad labels. Command: harden.
- [P3] 11 equal feature cards, names differ from the app, mixed capitalization. Fix: 3 grouped rows with app labels. Command: distill.

## Persona Red Flags
- Jordan: price/trial implies nags; Download → Buy; Accessibility unexplained; jargon names.
- Riley: dead Buy button; hello@example.com placeholder everywhere; leftover downloads/Brim-1.1.dmg test build; mailto lost-key form; no-JS page invisible; no source link.
- Casey: mobile nav shows only "Buy"; demo traps scroll (touch-action:none); no "send to my Mac"; .dmg to phone; long card stack.

## Minor Observations
- Demo OSD slides under sticky nav; corner zone swallows top of volume edge; duplicate CSS rules; redundant "Brim" h2 under icon; eyebrow/h2 repetition; sub-page nav pattern differs; theme-color mismatch.

## Questions to Consider
- Should the hero be the trackpad itself?
- Is open source the headline rather than a footnote?
- Do everyday users need 11 features, or three: feels good, safe, free?
