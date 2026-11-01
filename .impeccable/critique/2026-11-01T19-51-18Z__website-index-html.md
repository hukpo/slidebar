---
target: Brim website
total_score: 24
max_score: 36
na_heuristics: 7
p0_count: 1
p1_count: 2
target_identity: "file:/Users/hukpo/Projects/Brim/website/index.html"
target_fingerprint: "sha256:6a6b952000f5098ab384fbc8da450a655ced173e0c8e72abdb2d18146c89bd1b"
target_path: /Users/hukpo/Projects/Brim/website/index.html
timestamp: 2026-11-01T19-51-18Z
slug: website-index-html
---
# Critique (re-run): Brim website

Method: design review (A: ad26965aab5f97ea4) + deterministic detector (0 findings after fixes)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | Demo OSD + live region; download gives no own feedback |
| 2 | Match System / Real World | 4 | Plain language, Accessibility explained |
| 3 | User Control and Freedom | 3 | Ghost stops on touch; pad middle scrolls |
| 4 | Consistency and Standards | 3 | Mixed dt casing; legal pages differ slightly |
| 5 | Error Prevention | 2 | Phone guard covers hero only; Gatekeeper tip outdated |
| 6 | Recognition Rather Than Recall | 3 | Corner/keyboard map only in small text |
| 7 | Flexibility and Efficiency | n/a | One-action Persuade page |
| 8 | Aesthetic and Minimalist Design | 3 | "Free and open source" repeated; redundant group label |
| 9 | Error Recovery | 1 | Only recovery copy outdated; no contact |
| 10 | Help and Documentation | 2 | No menu-bar location, quit or uninstall help |
| **Total** | | **24/36** | **Acceptable (67%)** |

## Priority Issues
- [P0] Install path: unnotarized build; Control-click bypass removed in macOS 15. harden + clarify.
- [P1] "Open source" claimed with no source link or LICENSE. harden.
- [P1] Thin trust case for an Accessibility app (no maker/contact; no "what it doesn't do"). clarify.
- [P2] Phone guard incomplete (nav + #get still serve .dmg). adapt.
- [P2] No post-install orientation (menu bar icon, quit, uninstall); "Updates when you want them" contradicts auto-install. onboard.
