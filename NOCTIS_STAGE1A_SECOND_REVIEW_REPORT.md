# NOCTIS_STAGE1A_SECOND_REVIEW_REPORT.md

Second review of Stage 1A on branch `release/prelaunch-hardening` (HEAD `d0f0f28`, all changes uncommitted), covering the rework done after the first review (R-01 HealthKit, R-02 Coach statements). Read-only: no source, test, configuration or document in the repository was changed, nothing was committed, pushed, stashed or reset, and the second worktree is untouched (its diff hash is unchanged). The only file written is this report. The regenerated `NOCTIS_STAGE1A_SOURCE_DIFF.patch` was re-checked: it still matches the working tree exactly (identical SHA-256 to a fresh regeneration). Date: 2026-11-02.

**Independence limit, unchanged.** This is still the same AI session that wrote the code and the first review. To keep it honest, the second review did not re-read my own claims; it ran things I had not run before: two real-HealthKit negative controls, a probe of Recovery in a scratch copy, a search for every caller of the changed readers, and a check of every document statement that the rework could have made stale. It found two stale statements (S-01, S-02) and one product question (S-03).

## 1. Final recommendation

**STAGE 1A APPROVED WITH CONDITIONS.**

| Change | Classification |
| --- | --- |
| 1. HealthKit permission flow (PRIV-01 / X-26), after rework | **APPROVED WITH REMAINING DEVICE VERIFICATION**, once S-01 is corrected |
| 2. App-switcher privacy cover (SEC-05) | **APPROVED WITH REMAINING DEVICE VERIFICATION** (R-03, the keyboard over the cover, still needs a device check) |
| 3. Secure data export (SEC-03) | **APPROVED WITH REMAINING DEVICE VERIFICATION** |
| 4. Coach / Apple Intelligence disclosure (L-06 / X-06), after R-02 | **APPROVED WITH REMAINING DEVICE VERIFICATION** (the model path on an Apple Intelligence iPhone is not verified) |

**Conditions.**
1. **Before committing:** correct the stale statement in `Docs/PRIVACY_REPORT.md` (S-01) and the stale comment in `HealthDataStatus.swift` (S-02). Both are small and neither changes behaviour.
2. **Before release (not before committing):** the device checks in section 8, including R-03.
3. **Owner decisions, not defects:** S-03 (Recovery score depends on an optional grant) and R-04 (the system sheet's explanation names five kinds while onboarding asks for three).

R-01 and R-02 from the first review are resolved. R-03 to R-10 were out of scope for the rework and are unchanged.

## 2. What was reviewed and how

- **Rework diff:** `HealthDataProviding.swift` (two optional readers), the four repositories (`HomeRepository.swift:249`, `InsightsRepository.swift:132`, `RecoveryRepository.swift:92`, `ReviewRepository.swift:68, 95`), `MockHealthKitProvider.swift` (`requireAsked`, lines 172-205), `HealthAuthorizationFlowTests.swift` (13 tests), `Docs/store/APP_STORE_LISTING.md` (lines 104-105, 125). All read in full.
- **Every caller of the fetchers** (`grep` over `Sources`, `App`, `Widgets`, `Watch`): the only places that read resting heart rate are the four repositories (all now use `restingHeartRateIfAsked`) and `HealthDataStatusReader`, which already catches `.unauthorized` per kind. Respiratory rate is read only by `HealthDataStatusReader`. `HKHealthStore` / `import HealthKit` appear only in `HealthKitProvider.swift`; the widgets, Watch and intents read the app's snapshot, not HealthKit. **No remaining site throws "permission required" for an unasked optional kind.**
- **Simulator and runtime:** iPhone 18 Pro, iOS 27.0 (24A434), Xcode 27.0 (27A266a). No physical device. Nothing here proves device behaviour.

### Commands and results (this review)

| # | What | Result |
| --- | --- | --- |
| V1 | `xcodebuild test -scheme NoctisKit-Package -destination <iPhone 18 Pro> -only-testing:` HealthAuthorizationFlowTests, HealthStepTests, HealthBehaviourTests, ExportProtectionTests, PrivacyShieldTests, DataExportTests, PrivacyManifestTests, SourceHygieneTests, on the repository tree, DerivedData outside the repository | **61 tests in 8 suites passed** |
| V2 | Real HealthKit, signed Debug app, **control A: Health skipped** ("Continue without Health data"), relaunched past onboarding | Home shows **"Connect Apple Health to see your nights"** and the Connect button (`…/tool-results/mcp-Claude_Code_iOS_Simulator-blob-1793575173159-yee03b.png`). The genuinely-unasked state is preserved: the fix did not hide it. |
| V3 | Real HealthKit, **control B: all three kinds declined** ("Don't Allow"), relaunched | Home shows **"No sleep data yet"** (the empty state), no Connect button (`…blob-1793575233993-01zd6o.png`). A decline is read as no data, never as missing permission, never as "denied". |
| V4 | Real HealthKit, **all three granted** (from the rework run) | Home shows "No sleep data yet" (`…blob-1793573899676-2g3odg.png`); Settings, Health data shows "No Health data found", Connect Apple Health and five rows (`…blob-1793573917561-3l6obj.png`). |
| V5 | Probe in a scratch copy of the package (not in the repository): Recovery and Home with the mock asked for the core kinds only, versus all five | Core only: `dataState=ready`, Recovery score **67**, factor weights renormalised (sleep duration 0.4375). All five: **70**, sleep duration 0.35. Home `ready` in both. |
| V6 | Full package suite, Release build, symbol check, 39 signed UI tests | Not re-run; from the rework on the identical tree: 2,646 tests in 358 suites passed, Release 0 warnings, symbol check exit 0, 39 of 39 UI tests passed. |

**Not run in this review:** the NOCTIS-Store purchase scheme, other UI suites, any physical device, iOS 26.x, Instruments.

## 3. HealthKit rework (change 1)

**What is now correct.**
- Optional kinds: an unasked resting heart rate or respiratory rate reads as no data (`HealthDataProviding.swift:40-55`); core kinds still throw, so someone never asked about sleep still gets the permission state (V2, and the `aPersonWhoSkippedHealth…` test).
- Three real-HealthKit scenarios agree with the design: asked and allowed → empty state; asked and declined → empty state; not asked → Connect (V2, V3, V4).
- `.authorized` is used only as "the system's question was asked" (protocol comment, provider doc). Nothing treats it as read access. The new optional readers do not depend on it.
- The mock now throws for any unasked kind, matching what real HealthKit was seen to do, so the regression tests describe real behaviour. They failed before the fix (3 screens) and pass after.
- `HealthKitProvider.authorizationStatus(for:)` is correct and untouched by the rework.

**Edge cases checked.**
- Declined optional kinds (via Settings Connect) return nothing without an error; no throw path.
- `errorAuthorizationDenied` is also swallowed for the two optional readers; HealthKit does not use it for read queries, and a declined read returns empty, so this loses nothing.
- Locked device: `run` maps only denied/not-determined to `.unauthorized`; a locked store is `queryFailed`, which is **not** swallowed (still reported as a failure).
- Concurrency: the readers are plain `async` functions called from `async let`; no new shared state.
- Background refresher and Reviews now behave the same as Home (same reader).

### S-01 · Confirmed · Medium (document accuracy) · `Docs/PRIVACY_REPORT.md:105`
Item 2 still says `HealthKitProvider.authorizationStatus()` "asks HealthKit about all five kinds", that after onboarding "those screens may show 'Connect Apple Health' until the person connects again, and the person may see Apple's Health sheet twice", and "**Not run against real HealthKit** … not a confirmed bug". Each part is now false: the status check asks about the core kinds, the screens do not show Connect after the core question, and it **was** run against real HealthKit. The report is the owner's source for the App Store privacy answers and the project's rule is that it must match the code. **Recommendation:** rewrite item 2 to say what is true now (onboarding asks for three kinds, optional kinds are asked from Settings, an unasked optional kind reads as no data, checked on the simulator with real HealthKit), and keep the owner's decision on wording. **Blocks commit: yes (small edit).**

### S-02 · Confirmed · Minor · `NoctisCore/HealthDataStatus.swift:33-34`
The comment on `canRequestAccess` still says "The system's question has not been asked yet … Once it has been asked it never shows again." It now means "at least one of the five kinds has not been asked". **Recommendation:** update the comment. **Blocks:** no.

### S-03 · Confirmed (model), Not verified (UI) · Minor, product decision · Recovery depends on an optional grant
The probe (V5) shows the same night scoring **67** without resting heart rate and **70** with it, because the remaining factors' weights are renormalised. That is graceful, but a person who skips the optional kinds gets a slightly different number from a person who grants them, and nothing tells them. The Settings note says the two kinds "haven't been asked for yet, so they show no data" and offers Connect; it does not say that granting them refines Recovery. Not checked: how the Recovery screen draws a missing resting-heart-rate factor (the simulator's Health store is empty, so the screen is never past its empty state), and the note itself was never rendered (it appears only when data exists). **Recommendation:** owner decision: add one clause to the note ("Recovery is more precise with them"), or ask for all five in onboarding. **Blocks:** no.

### S-04 · Info · The note was verified in logic only
`health.canRequestAccess && health.hasAnyData` is held by the unit test `theHealthPageStillOffersTheTwoKindsOnboardingDidNotAsk`; the SwiftUI rendering of `HealthCopy.notAskedYet` was not exercised in any run.

### S-05 · Not verified · Data-present path on real HealthKit
The simulator's Health store is empty, so "core granted and real samples present" was verified only with the mock (probe and tests). The permission and empty paths were verified with real HealthKit.

### R-04 (still open) · Minor
The system sheet's "App Explanation" (the usage string) still lists five kinds above a sheet that lists three. Seen again in V2 and V3. Owner wording.

## 4. Coach statements (change 4)

The three corrected statements were re-checked against the code:
- Medical and crisis patterns never reach the model (`AIService.swift:159`: a pattern-matched scripted reply returns before any model call).
- An unrecognised question (`mayClassify`) is classified by the on-device model, and the classifier prompt is `"Question: \(question)"` with static instructions only (`FoundationModelsProvider.swift:43-46`): it reads only the question text, not the person's numbers.
- The fixed reply carries intent `.crisis`/`.medicalOutOfScope` whichever way it was reached (`CoachQuestionRouter.swift:138-155`), so the "crisis exchange is neither saved nor logged" statement holds for the classifier path too (`AIService.answer` returns before history and logging for crisis intent).
- "Every number is a value NOCTIS supplied" matches the validator (`digitInText`, `percentInText`, `numberWordInText`, `unknownToken`).

No inaccurate Coach statement remains in `APP_STORE_LISTING.md`, `SUBMIT_CHECKLIST.md`, `PRIVACY_REPORT.md` item 12 or `privacy.html`. Not verified on an Apple Intelligence iPhone.

## 5. Privacy cover and export (changes 2 and 3)

Not changed by the rework. Their tests were re-run (V1: `PrivacyShieldTests`, `ExportProtectionTests`, `DataExportTests`, `PrivacyManifestTests`, `SourceHygieneTests` passed). The first review's classification stands: APPROVED WITH REMAINING DEVICE VERIFICATION, with R-03 (keyboard over the cover), R-06, R-07 (cover on transient inactive moments, multi-scene), R-08 (export while locked) and R-09 (the system's copy of the shared file) still open for device checks. They were not re-examined beyond the test re-run.

## 6. Unrelated changes

None in source, tests or configuration. The patch contains 21 modified tracked files and 4 new source/test files; every file is in one of the four changes or the rework.

## 7. Failed or skipped tests

None failed in this review. One package test is reported skipped in the full-suite log (`renderLoadedPlanCards()`, pre-existing, conditional).

## 8. Physical-device checks still required

1. Onboarding on a real iPhone with real Health data: grant the three kinds, confirm Home and Recovery show data with no second prompt, then connect the two optional kinds from Settings and confirm Recovery changes (S-03, S-05).
2. The Settings note appears with data present (S-04).
3. Keyboard in the app switcher while typing a Journal entry (R-03); cover with VoiceOver; Control Center and system alerts (R-06, R-07).
4. Export while unlocked and while locked mid-share; confirm the protection class (R-08).
5. Coach on an Apple Intelligence iPhone and on one without it.
6. iOS 26.1 minimum (still never run).

## 9. Findings index (second review)

| ID | Severity | Status | Where | Needed |
| --- | --- | --- | --- | --- |
| S-01 | Medium (doc) | Confirmed | `Docs/PRIVACY_REPORT.md:105` | Edit before commit |
| S-02 | Minor | Confirmed | `HealthDataStatus.swift:33-34` | Comment fix |
| S-03 | Minor (product) | Confirmed (model) | Recovery with/without resting heart rate | Owner decision |
| S-04 | Info | Not verified (UI) | `HealthCopy.notAskedYet` | Device or UI check |
| S-05 | Info | Not verified | data-present path with real HealthKit | Device |
| R-03, R-04, R-06 to R-10 | as in the first review | open | | as in the first review |

## 10. Final assessment

**STAGE 1A APPROVED WITH CONDITIONS.** The rework fixes the defect: with real HealthKit, granting the three onboarding kinds, declining them, or skipping Health each produce the right state, and nothing in the app still throws "permission required" for an unasked optional kind. Correct the two stale statements (S-01, S-02) before committing, run the device checks before release, and decide S-03. Nothing is committed or pushed; Stage 1B has not been started.

## 11. Addendum: S-01 and S-02 corrected (2026-11-02)

At the owner's request, the two stale statements were corrected (documentation and a comment only; no behaviour changed):
- **S-01:** `Docs/PRIVACY_REPORT.md` item 2 now says what is true: onboarding asks for the three core kinds; the status check asks about those three only and means "asked", never "allowed"; an unasked optional kind reads as no data through `restingHeartRateIfAsked` and `respiratorySamplesIfAsked`; the simulator checks with real HealthKit (allowed, declined and skipped) and their results; that it was **not** checked on a physical iPhone or with real Health data; and the owner decisions that remain (S-03 wording, usage string).
- **S-02:** the comment on `HealthDataStatus.canRequestAccess` now says "at least one of the five kinds", with the onboarding example.

Re-run after the edits (iOS 27 simulator): PrivacyManifestTests, PrivacyEnforcementTests, PrivacyWordsComeFromTheInventoryTests, the DataInventory suites, HealthAuthorizationFlowTests, HealthBehaviourTests, HealthStepTests, SourceHygieneTests, SettingsTests and the Profile tests: **67 tests in 10 suites passed**. `git diff --check` is clean; the patch was regenerated and applies cleanly to the base. The review's condition 1 ("before committing") is met. Conditions 2 and 3 (device checks; owner decisions S-03 and R-04) are unchanged. Nothing is committed or pushed.

