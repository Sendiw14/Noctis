# NOCTIS_STAGE1A_REVIEW_REPORT.md

Independent code review of Stage 1A on branch `release/prelaunch-hardening` (HEAD `d0f0f28`, all changes uncommitted). Read-only: no source file, test, configuration or branch was changed, nothing was committed, pushed, stashed or reset, and the second worktree was not touched (its six modified files still hash identically to the backup). The only files written are this report and `NOCTIS_STAGE1A_SOURCE_DIFF.patch`. Date: 2026-11-02.

**Independence limit, stated plainly.** The same AI session that implemented Stage 1A also wrote this review, so it is not independent in the human sense. To compensate, the review went back to the base commit, read the actual diff, ran code and the simulator against it, and tested the claims in `NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md` rather than trusting them. It found that one of those claims is wrong (finding R-01). A reviewer who did not write the code should still look at R-01.

## 1. Final recommendation

**STAGE 1A NOT APPROVED, as submitted.**

| Change | Classification |
| --- | --- |
| 1. HealthKit permission flow (PRIV-01 / X-26) | **CHANGES REQUIRED** |
| 2. App-switcher privacy cover (SEC-05) | **APPROVED WITH REMAINING DEVICE VERIFICATION** (one simulator finding to check on a device: R-03) |
| 3. Secure data export (SEC-03) | **APPROVED WITH REMAINING DEVICE VERIFICATION** |
| 4. Coach / Apple Intelligence disclosure (L-06 / X-06) | **CHANGES REQUIRED** (two inaccurate sentences, R-02) |

Why not approved: the HealthKit change does not fix the defect it was written to fix. On real HealthKit (iOS 27 simulator), after granting exactly the three kinds onboarding asks for, Home still shows "Connect Apple Health". The implementation report said the opposite. Changes 2 and 3 are sound and can be kept. Change 4 needs two sentences corrected.

## 2. What was reviewed and how

- **Diff vs base:** `git diff d0f0f28` (17 tracked files, +133/-16) plus 4 new files (1 source, 3 test). All were read. `NOCTIS_STAGE1A_SOURCE_DIFF.patch` (888 lines, 21 files) contains every one of them. It applies cleanly to a `git archive` of `d0f0f28` and the result matches the working tree file for file (checked with `git apply --check` and `diff -r`). It deliberately excludes the report files (`APP_STORE_PRE_LAUNCH_AUDIT.md`, `NOCTIS_BACKUP_REPORT.md`, `NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md`, this report), which are documents, not source.
- **Unrelated changes:** none found in source, tests or configuration. Two empty directories that builds create are untracked/ignored (`Noctis.xcodeproj/project.xcworkspace/xcshareddata`, `Packages/NoctisKit/.swiftpm`); neither is part of the change.
- **Simulator and runtime:** iPhone 18 Pro, iOS 27.0 (24A434), Xcode 27.0 (27A266a). No physical device was used. Nothing here proves device behaviour.

### Commands run for this review (all outside the repository's files)

| # | Command | Result |
| --- | --- | --- |
| T1 | `xcodebuild test -project Noctis.xcodeproj -scheme Noctis -destination 'platform=iOS Simulator,id=<iPhone 18 Pro>' -derivedDataPath <scratch>/dd-ui -only-testing:NoctisUITests/HealthQATests -only-testing:NoctisUITests/OnboardingQATests -only-testing:NoctisUITests/RecoveryQATests CODE_SIGNING_ALLOWED=NO` on a copy of the working tree | 39 UI tests: **38 passed, 1 failed** (`OnboardingQATests.testHealthDeniedThenPlanWithoutHistory`: "HealthKit permission sheet did not appear") |
| T2 | the same single test with `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO` | **Passed.** The T1 failure was environmental: an unsigned build carries no HealthKit entitlement (`codesign` shows none), so the real sheet cannot appear. It says nothing about Stage 1A |
| T3 | Manual run of the signed Debug app on the simulator with real HealthKit (no mock flags) | See R-01 |
| T4 | Manual PrivacyShield scenarios on the same simulator | See section 5 |
| T5 | The package suite, Release build and symbol check from the implementation run | **Not re-run** in this review (the tree is byte-identical to the one that produced them: 2,644 tests in 358 suites passed, Release build 0 warnings, symbol check exit 0, `git diff --check` clean). That run included the privacy, inventory, export and Journal suites |

**Not run:** the NOCTIS-Store purchase scheme, other UI suites, any Settings UI test (there is no UI test class for the Health data page; none was run), Instruments, any device, any iOS 26.x.

## 3. HealthKit (change 1): CHANGES REQUIRED

### R-01 · Confirmed · Blocker for this change · The fix does not work on real HealthKit

**Evidence (real HealthKit, signed Debug app, iOS 27 simulator).**
1. Fresh install, onboarding Health step, "Connect Apple Health". The system sheet listed exactly **three** topics ("Select All 3 Topics": Heart Rate, Heart Rate Variability, Sleep). All three allowed.
2. Relaunched past onboarding without the mock. **Home showed "Your first night starts here. Connect Apple Health so NOCTIS can read your nights." with a Connect Apple Health button**: the permission-required state. (Screenshot: `…/tool-results/mcp-Claude_Code_iOS_Simulator-blob-1793571674794-5xv8dg.png`.)
3. Tapped Connect. The sheet now listed **only two** topics ("Select All 2 Topics": Resting Heart Rate, Respiratory Rate). So HealthKit does count the three core kinds as asked, which is what `authorizationStatus(for: core)` relies on. (`…blob-1793571690377-t7knk3.png`.)
4. Allowed those two. Home changed to **"No sleep data yet"** (the empty state). (`…blob-1793571730352-tt963v.png`.)

So the permission-required state disappeared only when **all five** kinds had been asked, exactly the condition Stage 1A set out to remove.

**Cause (code).** `HealthKitProvider.run` maps `HKError.errorAuthorizationNotDetermined` to `HealthProviderError.unauthorized` (`HealthKitProvider.swift:131-139`). Home, Insights, Recovery and the Reviews each fetch resting heart rate inside the same throwing group as the core data and treat `.unauthorized` as "permission required" (`HomeRepository.swift:249, 261`; `InsightsRepository.swift:132, 135`; `RecoveryRepository.swift:92, 96`; `ReviewRepository.swift:68, 95`). Resting heart rate was never asked for after onboarding, so the query throws, and the whole screen reports no permission. The status check now passes (core asked), but the data query still fails. The Settings Health page already anticipates this (`HealthDataStatus.swift:85-88` catches `.unauthorized` per kind "because the question has not been asked"), which is further evidence that the original authors knew an unasked kind throws.

**Why the tests did not catch it.** The updated mock returns an empty array for an unasked kind (`MockHealthKitProvider.swift:172-202`, comment "HealthKit returns nothing for it"). That was an assumption, and the simulator shows it is false: real HealthKit throws. The new tests therefore pass against behaviour HealthKit does not have. Test `aKindThatWasNeverAskedForReadsAsNoDataNotAsAnError` encodes the wrong behaviour.

**Impact.** The bug that PRIV-01 described (a person who just answered onboarding sees "Connect Apple Health" and a second prompt) is still there, with one difference: the second prompt now lists two topics instead of five. The implementation report's claims "Home loads after onboarding alone" and "FIXED BUT NOT FULLY VERIFIED" overstated this change; the correct status is NOT FIXED.

**Recommended solution (not implemented, per the rules).** Pick one and test it against real HealthKit:
1. Make an unasked **optional** kind read as no data: either catch `.unauthorized` per optional fetch (resting heart rate, respiratory rate) in the repositories, or have `HealthKitProvider` return `[]` for `errorAuthorizationNotDetermined` on those two kinds only.
2. Make the mock throw `.unauthorized` for an unasked kind, so the regression tests describe real behaviour; add a test that Home, Recovery, Insights and Reviews do not return permission-required when only the core kinds were asked.
3. Or ask for all five in onboarding (the original behaviour of the Connect flow); this was ruled out by the brief for sensitivity reasons.

### Other HealthKit observations

- **R-04 · Confirmed · Minor.** The system sheet's "App Explanation" (the `NSHealthShareUsageDescription`) names five kinds while onboarding's sheet asks for three. It is accurate for the app as a whole but may read as inconsistent to a reviewer. Consider wording that does not enumerate kinds the sheet is not asking for yet.
- **`.authorized` is not treated as read access.** Across the changed files `.authorized` is used only as "the question has been asked"; the protocol comment says so, and declined kinds are handled as no data. No place was found that treats it as proof of read access. (The defect in R-01 is the reverse: an unasked kind is treated as a missing permission for the whole screen.)
- **Three core kinds and five total.** Correct as defined (`HealthDataKind.core`), and `HealthStepFacts.requestedKinds` reads it. `authorizationStatus(for:)` with `read:` the core set matches how the sheet behaved in step 3 above.
- **Empty versus unavailable data.** Unchanged and correct: unavailable is its own state; an answered question with no data shows the empty state (seen in step 4).
- **Settings connection flow.** `canRequestAccess` now asks about all five, so "Connect Apple Health" stays available for the two unasked kinds; the sheet then lists only those two (seen). The new note (`HealthCopy.notAskedYet`) only appears when `canRequestAccess && hasAnyData`; it was not seen on the simulator because the Health store there is empty. Not exercised: **Not verified**.
- **Recovery without resting heart rate or respiratory rate.** Could not be assessed: with unasked resting heart rate the screen never gets that far (R-01).
- **Mock fidelity (R-05, Confirmed, Minor).** `authorizationStatus(for:)` in the mock returns `.notDetermined` when Health is unavailable, where the real provider returns `.unavailable`; callers check availability first, so nothing breaks today.
- **Background delivery.** The observer queries for an unasked kind complete their handler on error (`HealthKitProvider.swift` `BackgroundObservers`), so nothing hangs. `isAuthorized` for the background refresher (`AppContainer.swift:412`) is now true after the core question; the refresh then hits the same unasked-kind error. Same fix as R-01.
- **UI tests.** `HealthQATests` (6) and the Health-related Onboarding tests all pass signed or mock-driven, but none of them exercises "grant the core three, then see Home", which is why this was missed.

## 4. Coach disclosure (change 4): CHANGES REQUIRED

Compared against `AIService.swift`, `CoachQuestionRouter.swift`, `FoundationModelsProvider.swift`, `SystemLanguageModelBackend.swift`, `CoachSafetyValidator.swift`, `CoachHelplines.swift`.

**Accurate (checked):** on a supported iPhone with Apple Intelligence on, the on-device `SystemLanguageModel` writes a structured draft; the 15-second timeout and the template fallback; the validator list; `aiRemote` off with no transport; crisis exchanges not kept or logged (`answer()` returns before history for crisis intent); history excluded from backups; English only; availability mapped from the system's reasons.

### R-02 · Confirmed · Minor-to-Major (review-risk) · Two sentences are wrong

- `Docs/store/APP_STORE_LISTING.md:105` (reviewer notes) says medical and crisis replies "do not use the model or the person's data". `:125` (table) says "Scripted replies, no model, no data".
- The code: only questions that a **pattern** recognises as medical or crisis skip the model. A question no pattern recognises (`mayClassify`, `CoachQuestionRouter.swift:21`) is sent to the on-device model to be **classified**; if the model answers `crisis` or `medicalOutOfScope`, the fixed reply is shown (`AIService.swift:163-170`). In that path the model has read the question text. No personal data is given to it, but "do not use the model" is not true.
- **Recommendation:** say that the fixed replies contain no model-written text and no personal data, and that a question no pattern recognises is first classified by the on-device model, which reads only the question.
- Also soften "The model never invents numbers" (`APP_STORE_LISTING.md:104`): the validator blocks digits, percent signs and number words outside values NOCTIS supplies, but it cannot stop a correct number being attached to the wrong fact. Suggest "numbers are only ever values NOCTIS supplied".

Policy draft (`Docs/site/privacy.html`) and `PRIVACY_REPORT.md` item 12: consistent with the code. One sentence in the policy ("not sent to us or to any other service") is true of NOCTIS; Apple's on-device model is local. Not verified on an Apple Intelligence device.

## 5. PrivacyShield (change 2): APPROVED WITH REMAINING DEVICE VERIFICATION

### Code review (`AppRoot/PrivacyShield.swift`, `App/NoctisApp.swift:12-14`)

| Area | Finding |
| --- | --- |
| Lifecycle | `UIWindow(windowScene:)` is created on `willDeactivate`, hidden and its root controller released on `didActivate` (`:73-97`). Not made key. Held only while inactive. No retention found. |
| Observers | Registered once (`start()` guards `observers.isEmpty`, `:40`), on the main queue, with `[weak self]` and `MainActor.assumeIsolated`. Never removed: it is a process-lifetime singleton. Acceptable. |
| Concurrency | `@MainActor` class; closures extract the scene before entering the actor. No Swift 6 diagnostics (0 warnings). |
| Window level | `.alert + 1` (`:77`): above sheets, the paywall and the app's alerts. |
| R-06 · Potential · Minor | State is one `isCovering` flag and a notification with no scene (`object` not a `UIWindowScene`) covers or uncovers **every** connected scene (`:55-61, 73-95`). NOCTIS is single-scene on iPhone, so this cannot occur today; it would misbehave with several scenes (iPad, Stage Manager). |
| R-07 · Potential · Minor | The cover also appears for any short inactive moment (Control Center, Notification Center, system alerts such as the notification permission). Not exercised except the Health sheet (below). |
| Accessibility | The symbol is `accessibilityHidden`. When the cover is removed, VoiceOver focus may reset; **not verified** (device only). |
| State | Nothing under the cover is rebuilt; the paywall sheet, Journal draft text and wind-down timer were still in place on return (below). |

### Simulator results (T4, iPhone 18 Pro, iOS 27 simulator)

| Scenario | Result |
| --- | --- |
| Home with data (Recovery 70, 6h 42m), app switcher | Card shows only the cover (this was also seen in the implementation run). |
| Journal list (Reflect → Journal), app switcher | Cover only. Note: this app opens the Journal inside the Wind-down screen, not as a modal sheet. |
| **Keyboard visible** (Journal new entry, text field focused) | **The system keyboard, including the suggestion bar ("I", "Have", "Love"), is drawn above the cover in the switcher card** (`…blob-1793571812248-itovan.png`). The app content is hidden; the keyboard is not. See R-03. |
| **Paywall sheet** open, app switcher | Cover only; the sheet is hidden (`…blob-1793571835956-l32yx8.png`). |
| Repeated background/foreground (3 cycles) | Cover removed each time, paywall sheet and its state intact, no stuck cover (`…blob-1793571850298-bdyddv.png`). |
| Health authorization sheet | **Not obscured**: the sheet was fully visible and usable throughout (the cover did not appear over it). |
| Control Center / Notification Center transitions, notification permission alert, multi-scene | **Not exercised.** |

### R-03 · Confirmed on simulator, Potential on device · Medium · Keyboard shows over the cover

**Evidence:** above. **Impact:** a person typing a Journal entry who goes to the switcher leaves the keyboard and its QuickType suggestions (which can be predicted from what they typed) visible; the app content is not. On a device iOS may not include the keyboard in the snapshot; the simulator does. **Recommendation:** end editing when the scene is about to deactivate (resign first responder from the cover's coordinator, or dismiss the keyboard in the Journal field on `scenePhase != .active`), then verify on a device. **Blocks:** no, if the device check passes.

## 6. Secure export (change 3): APPROVED WITH REMAINING DEVICE VERIFICATION

Reviewed `DataExport.swift` (`write`, `remove`, `partialFileName`), `DataManager.exportFile/discardExport`, `DataWiring.swift:189-191`, `DataManagementViews.swift:8-16`.

| Area | Finding |
| --- | --- |
| Complete protection | `data.write(to: partial, options: [.completeFileProtection])`; the class survives the rename. Held by a source test and a platform check; the simulator reports no class, so the class itself is **device-only**. |
| Atomicity | Final file appears by `moveItem` / `replaceItemAt`: whole or absent. A second export replaces the first. |
| Interrupted write | The partial name is fixed and is removed on failure, by `discardExport()` (when Data management closes and at `DataManager` init) and by delete-all. No temporary file with an unknown name can be left by this code. |
| Concurrency | Two overlapping exports interleave only at `await build`; `write` runs without suspension on the main actor, so the partial file cannot be written by two calls at once. |
| R-08 · Potential · Minor | With complete protection the write **throws while the iPhone is locked**. Pre-change it succeeded. The export is started from the unlocked app, so this is rare; the error surfaces as a failed share. Not exercised on a device. |
| R-09 · Confirmed (pre-existing) · Minor | The export is handed to the share sheet through `FileRepresentation` and `SentTransferredFile`, which by default lets the system copy the file. That copy is outside the app's control and existed before this change; the new protection does not apply to it. Not changed, but relevant to "no unnecessary copies of the Journal text". |
| R-10 · Confirmed · Info | `NOCTIS-export.json.partial` is not listed in the data inventory (`DataInventory+Shared.swift:283`, which lists only the final name). It is transient and cleaned; the inventory tests still pass. Consider listing it for completeness. |
| Copies | No second copy of the data is written by NOCTIS: `exportFile` builds the data in memory and writes once. |
| Tests | The failing-write test (read-only folder), replacement, partial cleanup and no-stray-copy tests are meaningful and passed. They were not weakened. |

## 7. Regression risks

1. R-01: the main defect remains; any release relying on Stage 1A as submitted still shows "Connect Apple Health" after onboarding.
2. The mock now models "asked" kinds. Mock-driven UI flows that go through onboarding (QA matrix, `Docs/qa`) will differ for Recovery and Settings (no resting heart rate until connected). The UI suites run here did not fail on that, but the full QA matrix was not run.
3. New Settings note and Health page behaviour are untested in UI.
4. PrivacyShield: single `isCovering` flag; behaviour with multiple scenes is undefined (R-06).
5. Export: new failure mode while locked (R-08).
6. Dependency on Swift/UIKit notification names (`UIScene.willDeactivateNotification`): stable API.

## 8. Security and privacy concerns (summary)

- R-03 keyboard over the cover (Medium, device-verify).
- R-09 system copy of the export (pre-existing).
- R-02 documentation overstates what the Coach model does not see (disclosure accuracy; a review-rejection risk).
- No new data collection, no new network use, no new permissions, no new entitlements; the share set stays empty.

## 9. Test results (this review)

| Suite | Result |
| --- | --- |
| UI: HealthQATests (6), OnboardingQATests, RecoveryQATests, 39 tests, unsigned | 38 passed, **1 failed** (environmental, T1/T2) |
| UI: the failed test, signed ad hoc | **Passed** |
| Settings UI tests | none exist for the Health page; not run |
| Package suite / privacy / export suites | not re-run; from the identical tree: all passed (2,644 tests) |
| Real-HealthKit manual check (T3) | **Defect found (R-01)** |
| PrivacyShield manual checks (T4) | Passed for Home, Journal, paywall sheet and repeated transitions; keyboard finding R-03 |

**Failed or skipped:** the one UI failure above (explained); `renderLoadedPlanCards()` skipped in the package suite (pre-existing, conditional).

## 10. Physical-device checks still required

1. Real iPhone: onboarding → Home after granting only the core three kinds, with and without Health data (R-01 after it is fixed).
2. Keyboard in the app switcher while typing a Journal entry (R-03).
3. App switcher on a device from Home, Recovery, the Journal and the paywall; with VoiceOver on (focus after the cover is removed).
4. Control Center and Notification Center pulls, system permission alerts (cover flicker or obstruction).
5. Export while the iPhone is unlocked and while locked mid-share (R-08); confirm the file protection class.
6. Coach on an Apple Intelligence iPhone and on one without it (documents).
7. iOS 26.1 minimum (still never run).

## 11. File-by-file findings

| File | Verdict |
| --- | --- |
| `HealthProviding/HealthModels.swift` (`core`) | Correct. |
| `HealthProviding/HealthDataProviding.swift` | Reasonable seam and default; fine. |
| `HealthProviding/HealthKitProvider.swift` | Status query is correct for "asked"; **but** the unasked-kind error mapping (line 131) makes the screens fail (R-01). |
| `HealthProviding/Mock/MockHealthKitProvider.swift` | **Wrong model of HealthKit** (unasked kind returns `[]`); hides R-01 (R-01, R-05). DEBUG only. |
| `NoctisCore/HealthDataStatus.swift` | Correct (`canRequestAccess` over all five). |
| `OnboardingFeature/HealthScreen.swift` | Correct, same three kinds. |
| `ProfileFeature/SettingsContent.swift`, `SettingsPages.swift` | Note is accurate in its condition; untested in UI. |
| `AppRoot/PrivacyShield.swift` (new) | Sound; R-03, R-06, R-07. |
| `App/NoctisApp.swift` | Two lines, correct. |
| `NoctisCore/DataExport.swift`, `DataManager.swift`, `AppRoot/DataWiring.swift` | Sound; R-08, R-09, R-10. |
| `HealthAuthorizationFlowTests.swift` (new) | Encodes the wrong mock behaviour for an unasked kind (R-01); other tests valid. |
| `PrivacyShieldTests.swift` (new) | Meaningful for the lifecycle; waits use `waitFor`/`Task.yield` as the hygiene rule requires. Cannot see the switcher. |
| `ExportProtectionTests.swift` (new) | Meaningful; protection class is source-checked on the simulator. |
| `Docs/store/APP_STORE_LISTING.md` | **R-02 (two sentences).** |
| `Docs/store/SUBMIT_CHECKLIST.md`, `Docs/PRIVACY_REPORT.md`, `Docs/DEVICE_TEST_CHECKLIST.md`, `Docs/site/privacy.html` | Accurate. |

## 12. Findings index

| ID | Severity | Status | Where | Needed |
| --- | --- | --- | --- | --- |
| R-01 | Blocker (for change 1) | Confirmed | `HealthKitProvider.swift:131`; Home/Insights/Recovery/Review repositories; mock | Change required |
| R-02 | Minor-Major (disclosure) | Confirmed | `APP_STORE_LISTING.md:104,105,125` | Doc edit |
| R-03 | Medium | Confirmed (sim), Potential (device) | `PrivacyShield.swift` | Device check, then likely a small change |
| R-04 | Minor | Confirmed | usage string vs sheet | Optional wording |
| R-05 | Minor | Confirmed | mock availability answer | Optional |
| R-06 | Minor | Potential | `PrivacyShield.swift:55-95` | None for iPhone |
| R-07 | Minor | Potential | cover on transient inactive moments | Device check |
| R-08 | Minor | Potential | `DataExport.write` while locked | Device check |
| R-09 | Minor | Confirmed, pre-existing | `DataManagementViews.swift:14` | None required |
| R-10 | Info | Confirmed | inventory lacks the partial name | Optional |

## 13. Final assessment

**STAGE 1A NOT APPROVED.** Keep changes 2 and 3 and re-review them with the device checks above. Redo change 1 against real HealthKit (R-01), and correct change 4 (R-02). The implementation report should be corrected to say that the HealthKit item is NOT FIXED. Stage 1B has not been started.

## 14. Addendum: R-01 and R-02 addressed (2026-11-02)

Both findings were reworked at the owner's request; see `NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md` section 13 for the change, the before/after test evidence, the real-HealthKit simulator check and the results (full suite 2,646 passed, Release build 0 warnings, symbol check exit 0, 39 of 39 UI tests passed signed). R-01: with only the three core kinds granted, Home on real HealthKit now shows the empty state, not "Connect Apple Health". R-02: the three Coach statements are corrected and checked against the classifier prompt. R-03 to R-10 are unchanged and were not part of this request. The classification above (sections 1 to 13) is the original review and is kept as written; a second review of the rework has not been done.

