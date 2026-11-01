---
target: Brim macOS app UI
total_score: 29
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/Users/hukpo/Projects/Brim/Sources/Brim/Views"
timestamp: 2026-11-01T19-51-18Z
slug: sources-brim-views
---
# Critique (re-run): Brim macOS app UI

Method: design review only (detector not applicable, native platform)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | No Trackpad is a bare red pill; access-dependent toggles look active while Limited |
| 2 | Match System / Real World | 3 | "Limited", "Speed", "the More menu" opaque |
| 3 | User Control and Freedom | 3 | Access banner not dismissible; closing setup window isn't treated as finishing |
| 4 | Consistency and Standards | 3 | "Off in X" switch is inverted; power glyph = Quit beside an on/off switch |
| 5 | Error Prevention | 3 | Power icon quits without hint |
| 6 | Recognition Rather Than Recall | 3 | Draggable meters and clickable pill revealed only by tooltip |
| 7 | Flexibility and Efficiency | 3 | Shortcuts, Add last app, draggable meters |
| 8 | Aesthetic and Minimalist Design | 3 | Settings 16 flat controls; tick-heavy slider |
| 9 | Error Recovery | 2 | No-trackpad state has no notice or visible recovery |
| 10 | Help and Documentation | 3 | Guide reopenable; Limited explained only in tooltip |
| **Total** | | **29/40** | **Good** |

## Priority Issues
- [P1] Access banner can't be dismissed; yellow Limited pill nags an optional choice. clarify + quieter.
- [P1] Closing setup via window button reopens it every launch and skips the "Brim lives here" moment. harden/onboard.
- [P1] No-trackpad state lacks explanation and visible recovery. harden.
- [P2] Quit power icon ambiguous; "Off in X" inverted switch. clarify.
- [P2] Settings long and flat; access-dependent features unmarked. distill + layout.
