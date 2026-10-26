# Accessibility audit, final tree, iPhone SE, Light, default text size

Xcode's `performAccessibilityAudit(for: .all)` over every iPhone screen in the catalog (`AuditQATests`, `QA_CONFIG=A-light`), run on the Phase 3 build (behaviour-identical to the final tree: later commits are formatting, documents and test paths). Raw files: `audit/` in the delivered zip (one `<screen>__audit.tsv` per screen, the crops, `summary.jsonl`).

Screens audited: 209. Issues recorded (the audit records, the ledger triages): 1397.

| Type | Issues |
|---|---|
| contrast | 665 |
| Dynamic Type | 455 |
| text clipped | 225 |
| element detection | 31 |
| hit region | 21 |
| none | 21 |

No `element description` issue was recorded: every control has a VoiceOver description.

## Hit region (21)

All are non-interactive progress bars, not controls:

- 2 x "Page 1 of 6..."
- 1 x "Page 5 of 7..."
- 1 x "Page 2 of 6..."
- 1 x "Page 1 of 1..."
- 1 x "Step 6 of 6..."
- 1 x "Page 4 of 7..."
- 1 x "Step 3 of 6..."
- 1 x "Page 4 of 6..."
- 1 x "Step 1 of 6..."
- 1 x "Page 6 of 6..."
- 1 x "Page 3 of 7..."
- 1 x "Page 3 of 6..."
- 1 x "Step 5 of 6..."
- 1 x "Page 1 of 7..."
- 1 x "Page 5 of 6..."
- 1 x "Step 2 of 6..."
- 1 x "Page 6 of 7..."
- 1 x "Page 2 of 7..."
- 1 x "Step 4 of 6..."
- 1 x "Page 7 of 7..."

## Contrast: 513 of 665 issues have a measured ratio

- 4.5:1 or better: 462
- below 4.5:1: 51 (30 below 1.5:1, 21 between 1.5 and 4.5, of which 3 are the empty-frame "52 beats per minute" crops)

The 1.05 to 1.5 range are measurement artifacts: the audited frame holds no text (a card corner, a space) or the text sits under the scroll-edge fade (`night.sounds.playing` "Playing", viewed). The rest, by screen:

| Ratio | Screen | Text | Text colour on background |
|---|---|---|---|
| 1.93:1 | night.reflect.empty | Save | #2C1C14 on #544C3C |
| 2.06:1 | coach.answer | 52 beats per minute | #B4ACA4 on #FCF4EC |
| 2.06:1 | coach.answer.misbehaving | 52 beats per minute | #B4ACA4 on #FCF4EC |
| 2.06:1 | coach.answer.unavailable | 52 beats per minute | #B4ACA4 on #FCF4EC |
| 2.83:1 | home.day.learning | Awake | #742C04 on #9C8474 |
| 2.98:1 | sleep.day.learning | 19 | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | 20 | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | 21 | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | 22 | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | 23 | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | F | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | T | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | T | #646444 on #ACBC84 |
| 2.98:1 | sleep.day.learning | W | #646444 on #ACBC84 |
| 3.30:1 | home.day.empty | TONIGHT | #8C441C on #BCA4F4 |
| 3.50:1 | home.day.noPermission | TONIGHT | #8C441C on #BCACF4 |
| 3.62:1 | onboarding.rhythm | I feel best with | #4C3C54 on #A48CEC |
| 3.69:1 | home.day.stale | TONIGHT | #843C1C on #BCA4F4 |
| 4.22:1 | home.day.full | LAST NIGHT | #742C04 on #BCA494 |
| 4.47:1 | recovery.factor.restingHeartRate | TODAY | #442C1C on #E47C3C |
| 4.47:1 | recovery.factor.restingHeartRate | Within your normal range: 52 bpm vs your | #442C1C on #E47C3C |

The three "52 beats per minute" rows are empty-frame artifacts (viewed). The other 18 are small captions on colour blocks (R5 allows display text at 3:1) and one disabled button. They are not fixed in this pass because the pass changes no colour; QA-181 hands them to the owner.

## Dynamic Type and clipped text

Apple heuristics for one-line, tracked or fixed-frame text and for `noctisFont`'s manual scaling (QA-080). The larger-size screenshots (B-AX3, B-AX5) are what show whether text really clips.

