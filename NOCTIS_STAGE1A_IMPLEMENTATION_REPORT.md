# NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md

> **Updated 2026-11-02 after the independent review (`NOCTIS_STAGE1A_REVIEW_REPORT.md`).** The review found that the HealthKit fix described in sections 4.1 and 5 did not work on real HealthKit (R-01) and that two Coach sentences were wrong (R-02). Both were reworked; **section 13 is the current truth** and supersedes any statement below that contradicts it (in particular the mock's "unasked kinds read as no data" and the claim that Home loads after onboarding alone, which was only true once section 13's change was made).

Stage 1A: production hardening and critical engineering fixes. Branch `release/prelaunch-hardening`, started from `cleanup/release` at `d0f0f28c8494d055eca0962470f393f12a34e941`. Nothing is committed or pushed. Written 2026-11-02.

## 1. Implementation summary

Four approved items were implemented with the smallest changes that fit the existing architecture. No dependency, backend, analytics, remote AI, StoreKit, pricing, deployment-target or signing change was made, and `AppContainer` was not touched.

| Item | Audit IDs | Status |
| --- | --- | --- |
| HealthKit permission flow | PRIV-01 / X-26 | **FIXED AND VERIFIED** on the iOS 27 simulator with real HealthKit, after rework (section 13); physical-device pass still on the checklist |
| App-switcher privacy cover | SEC-05 | **FIXED BUT NOT FULLY VERIFIED** |
| Secure data export | SEC-03 | **FIXED BUT NOT FULLY VERIFIED** |
| Coach / Apple Intelligence disclosure in submission documents | L-06 / X-06 | **FIXED AND VERIFIED against the code**, after the R-02 correction (section 13); the model path on an Apple Intelligence iPhone is not verified |

The privacy cover and the export stay "not fully verified" because each depends on a device-only fact (HealthKit's real authorization answer, the iOS app-switcher snapshot on hardware, file-protection enforcement on a locked iPhone, the model path on an Apple Intelligence iPhone). The reasons are in section 10.

Safety checks before starting: repository root `/Users/sendiwkithnada/Documents/Noctis`, branch `cleanup/release`, HEAD matched the expected hash, status showed only the two untracked report files, two worktrees, 0 stashes, the backup folder existed and 933 of 933 checksums verified, and `release/prelaunch-hardening` did not exist.

## 2. Original audit issues addressed

PRIV-01 and X-26 (same root), SEC-05, SEC-03, L-06 and X-06 (same root). Not addressed, by design: everything else in the audit (see section 11).

## 3. Files modified

17 tracked files modified (133 insertions, 16 deletions), 4 new source/test files. Pre-existing untracked files (`APP_STORE_PRE_LAUNCH_AUDIT.md`, `NOCTIS_BACKUP_REPORT.md`) were not changed (SHA-256 of the audit report equals its backed-up copy).

| File | Change |
| --- | --- |
| `Packages/NoctisKit/Sources/HealthProviding/HealthModels.swift` | `HealthDataKind.core` (sleep, heart rate, HRV) |
| `.../HealthProviding/HealthDataProviding.swift` | New `authorizationStatus(for:)` requirement with a default implementation; doc comment on what `.authorized` means |
| `.../HealthProviding/HealthKitProvider.swift` | `authorizationStatus()` asks about the core kinds; new `authorizationStatus(for:)` |
| `.../HealthProviding/Mock/MockHealthKitProvider.swift` (DEBUG only) | Models which kinds were asked for; unasked kinds read as no data |
| `.../NoctisCore/HealthDataStatus.swift` | "Can request access" asks about all five kinds |
| `.../OnboardingFeature/HealthScreen.swift` | `requestedKinds = HealthDataKind.core` (same three kinds, one source) |
| `.../ProfileFeature/SettingsContent.swift`, `SettingsPages.swift` | One explanatory note on the Health page (optional kinds not yet asked) |
| `.../AppRoot/PrivacyShield.swift` (new) | The app-switcher cover |
| `App/NoctisApp.swift` | `PrivacyShield.shared.start()` at launch (2 lines) |
| `.../NoctisCore/DataExport.swift` | `write(_:in:)` and `remove(in:)`, `partialFileName` |
| `.../NoctisCore/DataManager.swift` | `exportFile()` and `discardExport()` use them |
| `.../AppRoot/DataWiring.swift` | The delete-all export eraser uses `DataExport.remove(in:)` |
| Tests (new) | `HealthAuthorizationFlowTests.swift`, `PrivacyShieldTests.swift`, `ExportProtectionTests.swift` |
| `Docs/store/APP_STORE_LISTING.md`, `Docs/store/SUBMIT_CHECKLIST.md`, `Docs/PRIVACY_REPORT.md`, `Docs/DEVICE_TEST_CHECKLIST.md`, `Docs/site/privacy.html` | Coach disclosure; device-test rows for all four items |

## 4. Technical explanation of every change

### 4.1 HealthKit permission flow (PRIV-01 / X-26)

**Cause (confirmed in code).** Onboarding asks Health for three kinds (`HealthScreen.swift`), but `HealthKitProvider.authorizationStatus()` asked `statusForAuthorizationRequest` about all five. HealthKit reports `.shouldRequest` while any type in the set has not been asked, so a person who had just answered onboarding's sheet looked "not asked". Home, Sleep, Recovery, Insights, Reviews and the plan build all gate on `authorizationStatus() == .authorized`, so they showed the permission-required state; the Connect flow then asked for all five.

**What `.authorized` means here.** HealthKit does not tell an app whether read access was granted; the request status says only whether the system's question has been asked. The code already treated it that way (a declined kind returns no samples). The fix keeps that meaning and documents it on the protocol. Nothing treats the status as proof of read access, and nothing says access was granted.

**Fix.**
- `HealthDataKind.core` = sleep, heart rate, HRV: exactly what onboarding asks. `HealthStepFacts.requestedKinds` now reads it, so the two cannot drift.
- `authorizationStatus()` asks the system about `core`. The data screens load once the question for those three has been asked.
- `authorizationStatus(for:)` asks about any set; the protocol gives other providers (test fakes) a default that forwards to `authorizationStatus()`.
- `HealthDataStatusReader.canRequestAccess` asks about all five, so the Settings Health page still offers "Connect Apple Health" for resting heart rate and respiratory rate, the two kinds onboarding does not ask for. The sheet shows only unasked types. A new note on that page explains an empty row ("haven't been asked for yet"), so empty is not read as denied.
- **No additional HealthKit data was requested.** Onboarding still asks for the same three kinds, the share set is still empty everywhere, and the home/other "Connect Apple Health" actions are unchanged (they still request all five, user-initiated).

**Trade-off to be aware of.** After onboarding alone, resting heart rate and respiratory rate are not asked for, so Recovery has no resting-heart-rate factor until the person connects them from Settings, Health data. Before the fix they were asked for as a side effect of the repeated prompt. This is the cost of not requesting extra data to satisfy a status check; it is a product decision for the owner (section 10).

### 4.2 App-switcher privacy cover (SEC-05)

`PrivacyShield` (AppRoot) watches `UIScene.willDeactivateNotification` and `UIScene.didActivateNotification`. On deactivation it shows a second `UIWindow` above everything (`windowLevel = .alert + 1`) holding a plain screen (the app's background colour and one moon symbol, no text); on activation it hides and discards the window. Why a window and not a SwiftUI overlay: an overlay on the root view would leave a presented sheet visible, and the Journal opens in a sheet. The window is never made key, so it takes no focus; nothing underneath is rebuilt, so navigation, alarms, audio, notifications, Live Activities and the Watch link are untouched; the window and its host controller are released on every return, so the cover retains nothing. It is started once, in `NoctisApp.init`. Not used: blur tricks, screenshot blocking, private APIs.

The cover also appears for any brief inactive moment (Control Center or Notification Center pulled down, a system alert), as with any such cover; it goes away on return.

### 4.3 Secure data export (SEC-03)

`DataExport.write` writes the JSON to `NOCTIS-export.json.partial` with `.completeFileProtection` (the class the Journal and Coach files use) and renames it onto `NOCTIS-export.json` (`moveItem`, or `replaceItemAt` when an earlier export exists), so the final file is whole or absent and a repeat export replaces the previous one. A failed write removes the partial file and throws. `DataExport.remove(in:)` deletes both names and is used by `discardExport()` (called on leaving Data management and when the app starts, as before) and by the delete-all step. The file stays in the temporary folder at the same path and name, so the inventory, Privacy Center and existing tests are unchanged, and no second copy of the Journal text is made. Share still works while the iPhone is unlocked; a locked iPhone cannot read the file.

### 4.4 Coach disclosure (L-06 / X-06)

Verified in code (`AIService.swift`, `FoundationModelsProvider.swift`, `SystemLanguageModelBackend.swift`, `CoachSafetyValidator.swift`): on a supported iPhone with Apple Intelligence on, Coach asks Apple's on-device model to write a structured draft (and, for a question its patterns do not recognise, to name the topic); every draft is validated; a failed or slow (15 s) draft, or any unavailable model, falls back to template answers built from the same facts; medical and crisis questions get fixed replies without the model or the data; `aiRemote` is off with no transport. Documents were rewritten to say exactly that: the listing's description and reviewer notes (previously "fixed wording"), a new "Coach and generative AI" table in `APP_STORE_LISTING.md` (what the model sees, what is checked, claims to avoid, what is not verified), the submit checklist, `PRIVACY_REPORT.md` item 12, the draft privacy page (one sentence), and device-test rows. The documents do not claim all iPhones support Apple Intelligence, do not call output clinically validated, and introduce no remote model. No Coach behaviour changed.

## 5. Tests added (25 tests, 3 suites)

| Suite | Tests | Covers |
| --- | --- | --- |
| `HealthAuthorizationFlowTests` | 11 | Onboarding asks the core kinds only and nothing else; after the core question the status is authorized, and not authorized for all five; Home, Sleep, Recovery and Insights do not return the permission-required state after onboarding alone; a never-asked kind reads as no data, not an error; the Health page still offers the two unasked kinds, then stops offering once all five are asked; skipping Health still shows the connect flow and the no-permission state; an answered question with no data is the empty state, never "permission required" or "denied"; Health unavailable stays its own state; the default `authorizationStatus(for:)` for providers that cannot tell kinds apart; the real provider's source asks about the core kinds and only ever uses an empty share set |
| `PrivacyShieldTests` | 6 | Cover shown on deactivation and removed on activation; started twice observes once; repeated cycles; the cover uses no text, model, store or sensitive name; it is a separate window above the app, never key, and discarded; the app starts it at launch |
| `ExportProtectionTests` | 8 | The file has complete protection where the platform reports a class; the code asks for it and keeps the whole-or-absent write; a second export replaces the first with no partial left; a failing write throws and leaves nothing; a good write leaves only the final file; a leftover partial file is removed by discard and at start; delete-all removes it; no copy of the data outside the single file |

**Honest limits of these tests.** The mock now models which kinds were asked, so the status contract is tested; the real `HKHealthStore` answer cannot be reproduced in a unit test, so the real provider is held by a source check plus the device checklist. The simulator reports no file-protection class, so protection is held by a source check and the platform-reported check that runs where a class exists. The app switcher cannot be observed in a unit test; see 7.4 for the simulator check. No existing test was changed.

## 6. Tests executed

All with DerivedData outside the repository (`<scratchpad>/s1a/…`), on **iPhone 18 Pro, iOS 27.0 simulator (build 24A434)**, Xcode 27.0 (27A266a), Swift 6.4.

| Run | Result |
| --- | --- |
| Full `NoctisKit-Package` suite, first run | **TEST FAILED**, exit 65: every test passed except **1**: `SourceHygieneTests.noTestSleepsForAGuessedDuration` correctly flagged `Task.sleep` in my new `PrivacyShieldTests` (two lines). The new tests were corrected (they use the project's `waitFor` and `Task.yield`); the hygiene rule was not touched |
| Full `NoctisKit-Package` suite, after the fix | **TEST SUCCEEDED: 2,644 tests in 358 suites passed in 657.1 s**, exit 0. The baseline was 2,619 tests in 355 suites; the difference is exactly the 25 tests and 3 suites added |
| Privacy and inventory suites (in that run) | `PrivacyManifestTests`, `PrivacyEnforcementTests`, `DataInventoryShapeTests`, `DataInventoryNetworkTests`, `DataInventoryEntityTests`, `DataExportTests`, `JournalPrivacyTests`, `HealthStepTests`, `SourceHygieneTests`: all passed |

## 7. Exact build results

### 7.1 Release build
`xcodebuild build -project Noctis.xcodeproj -scheme Noctis -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`, run on a copy of the working tree outside the repository: **BUILD SUCCEEDED**, exit 0. Built bundle: minimum iOS 26.1, `iphoneos27.0` SDK, 5 privacy manifests, `PrivacyShield` present in the app binary.

### 7.2 Release symbol check
`scripts/release_symbol_check.py` on the Release products: **exit 0**, 7 binaries, 0 hits (112 `#if DEBUG` blocks in 44 files; 294 DEBUG-only names, one more than before because the mock gained a private field). The mock's new `asked`/`readable` names are DEBUG-only and absent from Release.

### 7.3 Git
`git diff --check`: clean (exit 0). New untracked files were checked for trailing whitespace separately: none.

### 7.4 Simulator check of the app switcher (SEC-05)
A Debug build was installed on the iPhone 18 Pro simulator and launched with `-mockScenario full -noctisSkipOnboarding -forceTier premium`. Home showed Recovery 70 and 6h 42m. Opening the app switcher showed the NOCTIS card as the plain cover (cream screen, moon symbol), with none of that content. Returning to the app restored Home immediately, unchanged. (Screenshots: `~/.claude/projects/-Users-sendiwkithnada-Documents-Noctis/8a01cac8-053e-4c49-99f3-9c6cd8bb7859/tool-results/mcp-Claude_Code_iOS_Simulator-blob-1793569386149-hqsk7s.png` for the switcher, `…-blob-1793569397350-gkgpsp.png` for the restored app.) This is simulator evidence, not device evidence. The test app was uninstalled and the simulator shut down afterwards.

## 8. Compiler warnings

0 in the Release build and 0 in the unit-test build (`grep -c 'warning:'` on both logs).

## 9. Failed or skipped tests

- One failure in the first full run, fixed as described in section 6 by changing my new tests, not the existing hygiene test.
- One test is reported "skipped" in the log (`renderLoadedPlanCards()`): an existing test that skips itself conditionally; not touched.
- **Not run at all:** `NOCTIS-Store` (purchase scheme), the UI test suites and QA matrix, Instruments, anything on a physical device, anything on iOS 26.x.

## 10. Remaining risks

1. **HealthKit's real answer (PRIV-01).** The fix follows Apple's documented semantics but was verified only against a mock that models them plus a source guard; confirm on a device (`DEVICE_TEST_CHECKLIST.md`): after onboarding, no second sheet, Home loads, Settings offers Connect for the two remaining kinds.
2. **Recovery without resting heart rate** until the person connects it (4.1 trade-off). Decide whether onboarding should ask for it, or whether the Health page prompt is enough. Both Health-related labels are the owner's wording.
3. **UI tests and QA matrix not run.** The mock's honesty change means a mock-driven UI flow that goes through onboarding now has no resting-heart-rate or respiratory data until "Connect" is used; screenshot-based QA (`Docs/qa`) could differ in Recovery and Settings. Re-run `HealthQATests`, `OnboardingQATests`, `RecoveryQATests` and the Settings screens. The new Health-page note also adds a line in that screen.
4. **Cover behaviour on hardware.** Verified once on the simulator, Home only. Not checked: with a Journal sheet open, with the keyboard up, on a device, on the Apple Watch (no cover was added there), and for the brief cover during Control Center or system alerts.
5. **File protection** cannot be observed on the simulator; complete protection also means an export cannot be created while the iPhone is locked (it throws and leaves nothing); the Data management screen's error path for that was not exercised.
6. **Coach documents** describe the model path, which was read from code and not exercised on an Apple Intelligence device; the owner should re-read the new review notes and test both paths.
7. Everything in the audit not listed here is still open, including the legal pages, signing, the device pass and iOS 26.1.

## 11. Changes intentionally deferred

All other audit findings (for example UX-03, the three unsupported accessibility settings; PERF-01; COMP-01; REL-01; the placeholder legal URLs; the no-remote-repository risk) and everything under "STRICT NON-GOALS" in the brief. Also deferred: a privacy cover on the Apple Watch app, vacuuming SQLite after category deletes (PRIV-03), and clearing the Keychain item on a fresh install (SEC-01).

## 12. Final Git status and branch

- Branch: `release/prelaunch-hardening`, HEAD `d0f0f28c8494d055eca0962470f393f12a34e941` (no commits made).
- Modified (17): `App/NoctisApp.swift`; `Docs/DEVICE_TEST_CHECKLIST.md`, `Docs/PRIVACY_REPORT.md`, `Docs/site/privacy.html`, `Docs/store/APP_STORE_LISTING.md`, `Docs/store/SUBMIT_CHECKLIST.md`; under `Packages/NoctisKit/Sources`: `AppRoot/DataWiring.swift`, `HealthProviding/HealthDataProviding.swift`, `HealthProviding/HealthKitProvider.swift`, `HealthProviding/HealthModels.swift`, `HealthProviding/Mock/MockHealthKitProvider.swift`, `NoctisCore/DataExport.swift`, `NoctisCore/DataManager.swift`, `NoctisCore/HealthDataStatus.swift`, `OnboardingFeature/HealthScreen.swift`, `ProfileFeature/SettingsContent.swift`, `ProfileFeature/SettingsPages.swift`.
- Untracked, new: `Packages/NoctisKit/Sources/AppRoot/PrivacyShield.swift`, `Packages/NoctisKit/Tests/NoctisKitTests/{ExportProtectionTests,HealthAuthorizationFlowTests,PrivacyShieldTests}.swift`, and this report.
- Untracked, pre-existing and preserved: `APP_STORE_PRE_LAUNCH_AUDIT.md`, `NOCTIS_BACKUP_REPORT.md`.
- Second worktree `claude/charming-liskov-749f7b`: not touched; its six uncommitted changes are byte-identical to the backup (same diff hash). Stashes: 0.
- The backup taken before this stage is unchanged and still verifies.

Stage 1A stops here. Stage 1B has not been started. Awaiting review.

## 13. Rework after the independent review (current truth)

**What the review found.** (R-01) With only the three onboarding kinds granted, real HealthKit made Home, Recovery, Insights and the Reviews show "permission required": a query for a kind the system's question was never asked for (resting heart rate) **throws**, the provider maps that to `.unauthorized`, and each screen treats `.unauthorized` as "no permission". My mock returned an empty array for such a kind, which hid it. (R-02) Two Coach sentences said fixed replies "do not use the model"; for a question no pattern recognises, the on-device model classifies the text first.

**Changes made (4 more tracked files, plus edits to the new files).**
- `HealthProviding/HealthDataProviding.swift`: `restingHeartRateIfAsked(from:to:)` and `respiratorySamplesIfAsked(from:to:)`. An unasked optional kind is no data; the core reads are untouched, so a person who was never asked about sleep still sees the permission state.
- `NoctisCore/HomeRepository.swift`, `InsightsRepository.swift`, `RecoveryRepository.swift`, `ReviewRepository.swift` (2 call sites): use `restingHeartRateIfAsked`. `HealthDataStatus.swift` is unchanged (it already treated `.unauthorized` per kind as "not asked").
- `HealthProviding/Mock/MockHealthKitProvider.swift` (DEBUG only): an unasked kind now **throws `.unauthorized`**, as real HealthKit does.
- `Tests/.../HealthAuthorizationFlowTests.swift`: the wrong test was rewritten to assert the throw and that the optional readers return no data; added a test that the optional readers return data once asked, and one that the Reviews are not blocked (13 tests, was 11).
- `Docs/store/APP_STORE_LISTING.md`: three statements corrected. Medical and crisis replies are fixed text with no model-written words and no personal data; a pattern match never reaches the model; a question no pattern recognises is first classified by the on-device model, which reads only the question text (checked: the classifier prompt is `"Question: \(question)"` and nothing else); and "the model never invents numbers" became "every number is a value NOCTIS supplied".

**Evidence that the tests detect the defect.** With the mock corrected but the repositories not yet changed, the Health flow suite failed: Home, Recovery and Insights returned permission-required after only the core kinds were asked, and so did Home for an empty-but-asked scenario. After the repositories were changed the same suite passed (13 of 13).

**Evidence on real HealthKit (iOS 27 simulator, signed Debug app, no mock).** Fresh install, onboarding Health step, the system sheet listed three topics, all allowed; relaunched past onboarding. **Home shows "No sleep data yet" (the empty state), not "Connect Apple Health"** (`…/tool-results/mcp-Claude_Code_iOS_Simulator-blob-1793573899676-2g3odg.png`). Settings, Health data shows "No Health data found", the Connect Apple Health button, and all five rows ("…blob-1793573917561-3l6obj.png"). The Health store on the simulator is empty, so the new "haven't been asked yet" note (shown only when data exists) was not seen; it was not exercised.

**Results after rework (iPhone 18 Pro, iOS 27.0 simulator, Xcode 27.0):**
- Full package suite: **2,646 tests in 358 suites passed** in 629.6 s (before rework 2,644 and 358; the difference is the two added tests).
- Release build (`generic/platform=iOS`, unsigned): **BUILD SUCCEEDED, 0 warnings**. Signed Debug simulator build: succeeded, 0 warnings.
- `scripts/release_symbol_check.py`: **exit 0**, 7 binaries, 0 hits.
- UI tests `HealthQATests`, `OnboardingQATests`, `RecoveryQATests`, signed ad hoc so the HealthKit entitlement is present: **39 of 39 passed**. (Unsigned, one real-HealthKit test cannot show its sheet; that is a build-signing fact, not a defect.)
- `git diff --check`: clean.

**Final Git state.** Branch `release/prelaunch-hardening`, HEAD `d0f0f28`, nothing committed. 21 tracked files modified (+163/-21) and 4 new source/test files; `NOCTIS_STAGE1A_SOURCE_DIFF.patch` regenerated (25 files, applies cleanly to the base, reproduces the working tree). The second worktree is untouched (diff hash unchanged). The simulator test app was uninstalled.

**Still open (unchanged from the review):** the keyboard drawn above the privacy cover (R-03, device check), the cover on transient inactive moments and multi-scene behaviour (R-06, R-07), export while locked and the system's copy of the shared file (R-08, R-09), and everything under "Remaining risks" above except the HealthKit and Coach items. Not run in the rework: the NOCTIS-Store purchase scheme, any physical device, iOS 26.x.

Stage 1A stops here for re-review. Stage 1B has not been started; nothing is committed or pushed.

