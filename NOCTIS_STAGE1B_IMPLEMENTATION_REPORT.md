# NOCTIS_STAGE1B_IMPLEMENTATION_REPORT.md

Stage 1B implementation, written 2026-11-02; **updated after the corrective pass (section 8 onward).** **Nothing is committed and nothing is pushed.** The work is on branch `release/stage1b-hardening`, created from `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b`, as an uncommitted working tree for review. The second worktree was not touched.

Evidence labels as in the plan: **[V]** verified by a run or by reading source in this stage; **[N]** not verified; **[D]** needs a device, Sandbox or a real expiry.

## 1. What was built, against the approved plan

| Plan item | Result |
| --- | --- |
| S1B-C01 expiry-aware tier | Built. `WidgetSnapshot` carries `premiumUntil` and `autoRenews` (keys `pu`, `ar`); `effectiveTier(at:)` is the one reader; widgets, Siri/Shortcuts, Watch pages and Watch complications use it; the widget timeline has an entry at the lock moment. |
| S1B-C02 background entitlement refresh | Built. A Health background wake asks the store (`EntitlementManager.refresh()`) before it refreshes Home. |
| S1B-C03 billing-problem presentation | Built, wording is the owner's to approve. New `hasPaymentProblem` state, copy and a Manage subscription button. |
| S1B-C04 product metadata | Built. The subscription group is remembered in memory after the first product answer of a launch; later status reads use `Product.SubscriptionInfo.status(for:)`. |
| S1B-C05 Family Sharing | Not touched, as agreed. `Noctis.storekit` is unchanged. |
| S1B-D01 Watch expiry | Built with C01: the Watch computes `effectiveTier(at:)` locally. |
| S1B-D02 complication wake on plan change | Built. A change of tier or end of Premium wakes the complication once, within the existing budget. |
| S1B-D03 Watch Dock/app-switcher privacy | Not changed: it needs the device pass first [D], as the plan says. |
| S1B-B01 migration readiness | Built: `SchemaFingerprintTests`, `Docs/MIGRATION_PROCEDURE.md`. No artificial V2. |
| S1B-B02 interrupted delete-all | Built: marker `noctis.deleteAll.pending`, resume at launch, app starts over. |
| S1B-B03 SQLite compaction | Built (the owner's option to defer was not taken; no free-space check, see section 5): `StoreCompaction`, requested by a per-category delete, run once at the next launch before anything opens a database. |
| S1B-B04 Keychain after reinstall | Built: `FreshInstallGuard`. |
| S1B-B05 backup wording | Proposed wording added to `Docs/PRIVACY_REPORT.md` only; not put on the site or the listing. |
| S1B-B06 inventory coverage | No new code: the existing inventory tests cover it; the new keys were added to the inventory and its tests pass. |
| S1B-A01 Button Shapes | Built for text-only buttons (`noctisButtonShape()`): `NoctisTextButton` and five text links. |
| S1B-A02 Differentiate Without Color, S1B-A12 chart text | **Not changed.** See section 4. |
| S1B-A03 Smart Invert | Built: both share-card previews opt out; a scan test covers every `Image(uiImage:)`. |
| S1B-A04 to A11 | Verification items; not run in this stage [N]. |

## 2. Files

Modified (29) and added (10 source, test and doc files); the full list is `git status` on the branch. Source areas: `NoctisWidgetKit` (snapshot, timeline, gate, spoken), `NoctisCore` (publisher, maker, entitlement manager and client, summary, data manager, inventory, Watch sync), `NoctisIntentKit`, `NoctisWatchKit`, `AppRoot/AppContainer.swift`, `App/NoctisApp.swift`, `DesignSystem`, `OnboardingFeature`, `NightFeature`, `HomeFeature`, `InsightsFeature`, `ProfileFeature`. Docs: `PRIVACY_REPORT.md`, `POST_LAUNCH.md`, new `MIGRATION_PROCEDURE.md`.

## 3. Design decisions made while building (all small, none changes the plan's intent)

- **The end date is not kept anywhere new.** `EntitlementCache` stays one word. If the publisher writes before the store has answered after a launch, it keeps the end already in the file for the same plan, so a Home refresh that runs first does not drop it.
- **A grace period never gets the renewal slack**: it ends at its own end and `autoRenews` is false there.
- **Renewal slack is `WidgetSnapshot.renewalSlack` = 48 hours**, the plan's proposal. It is one constant; the owner confirms it before release.
- **A renewal that keeps the tier republishes the snapshot** through a new `onPremiumWindowChange` hook, since `onTierChange` does not fire for it.
- **Delete-all resume runs the whole list once and always clears its marker**, so a step that cannot work cannot make every launch start over.
- **Compaction waits** (marker kept) when the file cannot be opened for writing (a locked iPhone, another connection) and runs once per request otherwise. It never runs on a file SQLite calls damaged or larger than 32 MB. It does not check free disk space (see section 5).
- **The Keychain guard needs both conditions** (no marker and no database) before it clears anything, so an update or a restore that lost the marker keeps the sign-in.
- **The snapshot's privacy text changed** (the inventory entry and `PRIVACY_REPORT.md` now say the file holds the end date and the renewal flag).

## 4. What was not done, and why

- **S1B-A02 Differentiate Without Color and S1B-A12 chart descriptions: no code.** I looked for colour-only meaning and did not find a case in the places I sampled: the insight tile tints are decoration beside a title and value; the HRV and resting-heart-rate range is spoken in words; the night chart encodes the stage by position as well as colour. The sample was a few files, not every screen [N]. This needs the planned simulator pass with the setting on, so it is left for 1B-5 rather than guessed at.
- **The Tier C settings, the AX3 and AX5 re-shoot, VoiceOver traversal, touch targets, Bold Text, Reduce Transparency, Increase Contrast checks (S1B-A04 to A11): not run [N].**
- **Apple documentation was not re-checked from the Apple pages** for the Watch Dock snapshot, renewal timing or complication budgets; the code relies only on what the existing tests and APIs show.
- **Not run:** the UI tests (see section 5 for what was run). The one StoreKit-client change (C04) passed the NOCTIS-Store scheme twice after a failed first run (section 5); the real App Store behaviour of the group status call is [D].
- **Not verifiable here [D]:** a real expiry with the app closed and the widget flipping, a late renewal, the complication wake budget, the Watch Dock, kill mid delete-all, Keychain behaviour after a real reinstall, `VACUUM` on a real store.

## 5. Tests

All on the iPhone 18 Pro, iOS 27.0 simulator, Xcode 27, DerivedData outside the repository.

- **Full package suite: 2,713 tests in 373 suites passed** (648.7 s, `xcodebuild test -scheme NoctisKit-Package`). The Stage 1A baseline was 2,646 in 358: 67 new tests in 15 new suites, no existing test changed except two allow-lists (below).
- **Release build** (`generic/platform=iOS`, unsigned, on a copy of the working tree outside the repository): BUILD SUCCEEDED, 0 warnings. It builds the app, both widget extensions and the Watch app with its complications.
- **`scripts/release_symbol_check.py`**: exit 0, 7 binaries, 0 hits.
- **NOCTIS-Store (StoreKitTest, `SKTestSession` over `Noctis.storekit`, app-hosted): 24 tests, all pass with 1 known issue**, the same result as the base commit `2b4e7c8` (run on a clean copy of it for the comparison). My tree was run three times: the **first run failed** (every test that buys a plan failed because no product had loaded, 'store.products.first' was empty, in a derived-data folder that had never run StoreKit); the second and third runs passed, 24 of 24. The base commit passed on its first run. I did not find the cause of the first failure; it looks like a cold start of StoreKit in a new build folder, but that is a guess, not a finding [N]. It exercises the one StoreKit-client change (C04).
- New suites: `EffectiveTierTests`, `PremiumEndCodingTests`, `ExpiryTimelineTests`, `ExpirySurfaceTests`, `SnapshotTierReadersTests`, `PremiumWindowPublishingTests`, `PremiumWindowFromTheStoreTests`, `PremiumWiringTests`, `FreshInstallGuardTests`, `DeleteAllResumeTests`, `StoreCompactionTests`, `StoreCompactionRequestTests`, `SchemaFingerprintTests`, `ButtonShapeTests`, `SmartInvertTests`; three tests added to `WatchSyncServiceTests`.

**What the first full run caught, and what was done about it (both were my changes):**

1. `WidgetSnapshotShapeTests` is a deliberate allow-list of every key the snapshot may carry; the new key `ar` (and `pu` for Premium) were not on it. Both were added: the new keys are the plan's intent, and the test still guards against any other key.
2. `PrivacyManifestTests` found that the first version of the compaction asked the system how much disk space was free, which is a required-reason API (`NSPrivacyAccessedAPICategoryDiskSpace`) that the app does not declare, and that the test pins the declared set to `UserDefaults` only. **I did not change the privacy manifests.** The compaction no longer asks about free space: it compacts only files up to 32 MB (the real stores are kilobytes to a few megabytes), and a full disk makes `VACUUM` fail cleanly, in which case the request waits for the next launch. This is a deviation from the plan, which had a free-space check. If the owner prefers the free-space check, the alternative is to declare `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` in the app manifest; that changes the App Store privacy declaration and is the owner's call.

**Not run in this stage:** the UI tests, the Tier C accessibility settings, the Watch paired-simulator script, any physical device or Sandbox check.

## 6. Owner decisions still open

1. Confirm the 48-hour renewal slack (`WidgetSnapshot.renewalSlack`).
2. Approve the payment-problem wording (`SubscriptionSummary.detail`).
3. Approve the new-phone and backup wording in `PRIVACY_REPORT.md` before it goes on the site.
4. Family Sharing stays off until decided.
5. Carried from Stage 1A: the resting-heart-rate wording (S-03) and the usage-string question (R-04).

## 7. State of the repository

Branch `release/stage1b-hardening`, HEAD `2b4e7c8` (unchanged), changes uncommitted, nothing staged, no stash, no remote, the second worktree untouched. The backup of Stage 1A is unchanged; **this work is not in any backup yet.**


---

## 8. Corrective pass (after the independent review)

Branch `release/stage1b-hardening`, HEAD `2b4e7c8` (unchanged), all changes uncommitted, second worktree untouched (its `git diff --binary` hash is still `83a81df85233c1d2`), backups unchanged (the original and the post-Stage-1A one; **Stage 1B is in no backup**). Stage 1B is **not declared complete**: see section 12.

### 8.1 What changed, by priority, with the impact of each change

| Priority | Finding | Change | Impact |
| --- | --- | --- | --- |
| 1 | R-02 | `AppContainer` starts finishing an interrupted delete-all at creation, once per process; `NoctisApp` waits for it and restarts. The Health-wake refresher and the Watch's update request do nothing while a delete-all is unfinished | A background launch can no longer republish a half-deleted app's summary or send the Watch numbers |
| 1 | R-03 | The "Removing database files" step fails when a file cannot be removed (`FilesNotRemoved`). The marker counts attempts (three launches). **After the last attempt the marker is replaced by a persistent record (`noctis.deleteAll.unfinished`), and Data management shows a "NEEDS ATTENTION" card naming the steps and pointing at "Delete all NOCTIS data".** A delete-all that works clears it. `DataWiring` passes its defaults to `DataManager` | Deletion is never reported as done while a database file remains, the marker is never dropped silently, and the person is told. **One new visible element**: the card, shown only after a deletion that could not finish |
| 2 | R-04 | `PRAGMA temp_store = MEMORY` before `VACUUM`; cap 16 MB | The compacted copy of Journal and Coach rows is no longer written to the temporary folder. Measured, see 8.2 |
| 3 | R-05 | Real-store tests; the file list is built only when a request is pending | A launch with no request is one flag read (about 1 ms measured) |
| 4 | R-01 | The wake's order lives in `BackgroundRefresher.healthThenPlan`; failure and timeout paths tested | Health is written before the store is asked |
| 5 | R-06 | Button Shapes uses the text's own underline; removed from the Paywall footer links | Same colour and weight as the text; no double decoration |
| 5 | R-11 | "Premium paused" headline and "Your payment needs attention." page line | A paused plan is no longer called the free plan; **one wording change, only in that state** |
| 6 | R-12 | Migration doc and the new-phone wording corrected | Documentation |
| 6 | R-16 | `KeychainLookup`: not found and cannot ask are different; cannot ask spends nothing | A locked iPhone cannot consume the install marker |
| 6 | R-08 | Product-load retry in the StoreKit test helper; all logs kept | Test reliability only |

Not changed on purpose: the privacy manifests; R-07 (owner decision); R-14 (open); R-21 (pre-existing, owner decision); R-09, R-10, R-19 (Low, unchanged).

### 8.2 Evidence

- **SQLite temporary storage (R-04), measured.** Mac system SQLite 3.54 (`TEMP_STORE=1`), `VACUUM` of a 470 MB WAL database (`Docs/evidence/stage1b/probe2.py`): default, a file `etilqs_…` appeared in the temporary folder (seen with `lsof`) and resident memory peaked at 186 MB; with `temp_store = MEMORY`, no temporary file and 633 MB. iOS Simulator, in the test process (`StoreCompactionRealStoreTests.compactionWritesNoTemporaryFileWhereTheDefaultDoes`): the default `VACUUM` of a 30 MB store showed the temporary file; `compact` did not. **Not measured on a device.**
- **Real stores (R-05)**, Mac simulator: Journal 12.2 MB to 1.4 MB in 16 ms; Coach 2.3 MB to 1.8 MB in 15 ms; app database 3.0 MB to 2.5 MB in 21 ms; every kept row read back through the real container; protection and backup attributes unchanged. **Device timing is not measured.**
- **Resume (R-02)**, simulator, instrumented throwaway copy outside the repository: with the marker set, a launch with no root view resumed from container creation and ran all 47 steps in about 0.2 s; a foreground launch resumed once and restarted once with no second resume (`resume-simulator-log.txt`). A first attempt at this check failed because a preference file edited from outside the app is not seen by it (R-22); the second used the launch argument.
- **Screenshots** (`Docs/evidence/stage1b/screenshots/`, 32 files): Subscription page free and payment-problem, base build against after, light, dark and AX5 (large and accessibility-extra-extra-extra-large), Button Shapes off and on; Paywall base against after with Button Shapes on and off, light, dark and AX5; Home with Button Shapes on; the resume launches. **Button Shapes off is pixel-identical to the base build** on the Subscription page in all three configurations (compared below the status bar); on the Paywall, shapes off differs from the base only in the animated header (stars) and the clock, nothing below it. Not captured: the wind-down End control, onboarding secondary buttons, the share sheets, the "needs attention" card.

### 8.3 Pre-existing defect the screenshots showed (R-21)

With Button Shapes on, the Paywall footer links (system buttons laid out with negative padding) draw overlapping grey pills, and at AX5 the "Privacy" link is hidden. The base build is the same. Not changed; owner decision.

### 8.4 Owner decisions, none assumed

1. **R-07, the 48-hour renewal slack.** Choices: keep 48 hours (widgets, Watch and Siri may stay Premium up to two days after a failed renewal when the app does not run; a late renewal never locks a payer); shorten it (less drift, a small chance of locking a payer whose renewal completes late); or remove it (locks at the end date exactly, with the false-lock risk). Cancellations, refunds and revocations made while the app is closed are not seen by those surfaces until the app runs, whichever length is chosen. A Sandbox check of a late renewal [D] would inform this; nothing was assumed.
2. The payment-problem wording, including "Premium paused".
3. The new-phone and backup wording (corrected for the alarm).
4. Family Sharing: off.
5. **The disk-space check for compaction**: dropped because asking the system for free space is a required-reason API the app does not declare; replaced by the 16 MB cap. If the owner wants the check, declare `NSPrivacyAccessedAPICategoryDiskSpace` (reason `E174.1`): **a privacy-manifest change that needs approval**. Not made.
6. **R-21**: whether to change the Paywall footer layout for Button Shapes.
7. Whether the offline cold-start payment-problem state may be persisted (new stored data).
8. Whether `Docs/site/privacy.html` should say the widget file holds the plan end.

## 9. Changed files (exact)

Modified (36 tracked files): `App/NoctisApp.swift`; `Docs/POST_LAUNCH.md`; `Docs/PRIVACY_REPORT.md`; `Tests/StoreTests/StoreKitSessionTests.swift`; in `Packages/NoctisKit/Sources/`: `AppRoot/AppContainer.swift`, `AppRoot/DataWiring.swift`, `DesignSystem/NoctisCTA.swift`, `DesignSystem/OnboardingStepScaffold.swift`, `HomeFeature/HomeShare.swift`, `InsightsFeature/ReviewShare.swift`, `NightFeature/WindDownScreen.swift`, `NoctisCore/Account/AccountStore.swift`, `NoctisCore/BackgroundRefresher.swift`, `NoctisCore/DataInventory+Shared.swift`, `NoctisCore/DataManager.swift`, `NoctisCore/Store/EntitlementClient.swift`, `NoctisCore/Store/EntitlementManager.swift`, `NoctisCore/SubscriptionSummary.swift`, `NoctisCore/WatchSync/WatchSyncDefaults.swift`, `NoctisCore/WatchSync/WatchSyncService.swift`, `NoctisCore/WidgetPublisher.swift`, `NoctisCore/WidgetSnapshotMaker.swift`, `NoctisIntentKit/IntentRuntime.swift`, `NoctisIntentKit/ShowIntents.swift`, `NoctisWatchKit/WatchComplications.swift`, `NoctisWatchKit/WatchPages.swift`, `NoctisWidgetKit/WidgetGate.swift`, `NoctisWidgetKit/WidgetSnapshot.swift`, `NoctisWidgetKit/WidgetSpoken.swift`, `NoctisWidgetKit/WidgetTimeline.swift`, `OnboardingFeature/PaywallScreen.swift`, `ProfileFeature/DataManagementContent.swift`, `ProfileFeature/DataManagementViews.swift`, `ProfileFeature/SettingsPages.swift`; in `Packages/NoctisKit/Tests/NoctisKitTests/`: `WatchSyncTests.swift`, `WidgetSnapshotTests.swift`.

Added (untracked): `Docs/MIGRATION_PROCEDURE.md`, `Docs/ACCESSIBILITY_TEST_MATRIX.md`, `Docs/evidence/stage1b/` (logs, probes, screenshots), `Packages/NoctisKit/Sources/DesignSystem/NoctisButtonShape.swift`, `Packages/NoctisKit/Sources/NoctisCore/Account/FreshInstallGuard.swift`, `Packages/NoctisKit/Sources/NoctisCore/StoreCompaction.swift`, and the test files `ButtonShapeTests`, `DeleteAllResumeTests`, `FreshInstallGuardTests`, `PremiumExpiryTests`, `SchemaFingerprintTests`, `StoreCompactionRealStoreTests`, `StoreCompactionTests` in `Packages/NoctisKit/Tests/NoctisKitTests/`.

Reports in the repository root (untracked): this report, `NOCTIS_STAGE1B_INDEPENDENT_REVIEW.md`, `NOCTIS_STAGE1B_IMPLEMENTATION_PLAN.md`, `NOCTIS_STAGE1B_SOURCE_DIFF.patch` (regenerated after the corrective pass).

## 10. Test results (corrective pass)

All on the iPhone 18 Pro simulator, iOS 27.0, Xcode 27, DerivedData outside the repository; every log is kept in `Docs/evidence/stage1b/`.

- **Full package suite, final run: **2,738 tests in 376 suites passed** (673 s; the Stage 1A baseline was 2,646 in 358, so Stage 1B adds 92 tests in 18 suites).** Earlier runs in this pass and what they found: run 3 failed `noPluralIsMadeByHandWhereACountIsPrinted` (a hand-made plural in the new `FilesNotRemoved` message: fixed); run 4 failed three of my own new tests (a guessed `Task.sleep` in the wake tests, a timing-dependent control in the temporary-file test, a 0.3 s budget in the hung-store test, all of which only fail on a busy machine): made deterministic with gates and an injected sleep, and the temporary-file control now retries and falls back to a source check. The logs of the failing runs are kept next to the passing ones.
- **New and changed tests in this pass** (all pass in the final run): `DeleteAllResumeTests` 15 (bounded attempts, persistent record, relaunch, notice copy, gate on background work, container-start check) and `DeleteAllFileFailureTests` 2 (real immutable file through the real wiring); `StoreCompactionRealStoreTests` 5 (Journal, Coach, app database, launch cost, temporary-file evidence); `StoreCompactionTests` 12; `WakeBudgetTests` 3 (hung store, slow Health, failing store); `FreshInstallGuardTests` 9 (including a Keychain that cannot be asked yet); `ButtonShapeTests` 9 (render: off identical, on underlines, colour, wrapped lines, size; footer not shaped twice) and `SmartInvertTests`; `PremiumWindowFromTheStoreTests` (paused-plan wording).
- **NOCTIS-Store (StoreKit)**: 24 of 24 with the 1 known issue, three runs in this pass (`store-final-run1..3.log`), after eight earlier passes and the one unexplained first failure.
- **Release build** (`generic/platform=iOS`, unsigned, on a copy outside the repository): BUILD SUCCEEDED, 0 warnings; `scripts/release_symbol_check.py`: exit 0, 7 binaries, 0 hits. Run before the last test-only edits; no source changed after it.
- **Not run:** UI tests, any device, Sandbox, TestFlight, the Watch paired-simulator script, Instruments.

## 11. Remaining device and Sandbox verification (none of this was done)

1. A real plan end with the app closed: Medium/Large and Lock Screen widgets and Watch complications flip at the lock moment; a late renewal inside the slack does not lock; cancellation, refund and revocation while closed (how long until each surface changes); a Shortcut after the end (R-07).
2. A Health wake on a slow or absent network: Home still refreshes inside the 20 s budget (R-01).
3. Delete-all killed at several steps, then a background launch (a real Health wake) and a foreground launch: nothing deleted comes back on the widgets, Watch or screens; the "needs attention" card after three failed resumes (R-02, R-03).
4. Compaction on a device store after deleting Journal entries, with the iPhone locked at launch; timing on a device; the Journal and Coach protection class after `VACUUM` on a device (R-04, R-05).
5. A real reinstall, update and offloaded app with a signed build: the Keychain sign-in is cleared only on a reinstall; the lookup is `unavailable` before the first unlock (R-16). The ad-hoc simulator build has no Keychain entitlement, so none of this ran.
6. Watch: the Dock and app-switcher snapshot, complication refresh after a purchase or lapse (the transfer arrives, the remaining-budget log), disconnected deletion then a new snapshot, Always-On redaction.
7. Sandbox or TestFlight: purchase, trial, renewal, cancellation, refund, restore on a second install, Ask to Buy, billing retry and grace lengths, Family Sharing (if ever enabled), offline cold launch with a payment problem.
8. Accessibility: the whole of `Docs/ACCESSIBILITY_TEST_MATRIX.md` (R-14 stays open).
9. Screenshots not taken: wind-down End, onboarding secondary buttons, share sheets with Smart Invert, the "needs attention" card, the Paywall footer after a fix for R-21.

## 12. Risk register

| ID | Risk | Likelihood | Impact | State | Owner or next step |
| --- | --- | --- | --- | --- | --- |
| R-07 | Surfaces outside the app stay Premium for up to 48 h after a failed renewal; cancel, refund and revoke unseen while closed | Medium | Revenue and trust, no data | **Open: owner decision** | Choose the slack; Sandbox check of a late renewal |
| R-14 | Display settings largely unsupported or unverified (UX-03 open) | Certain for some users | Usability for people using them | **Open** | Run the matrix; code only for what reproduces |
| R-21 | Paywall footer overlaps with Button Shapes (pre-existing) | Certain with the setting on | Layout | Open: owner decision | Approve a footer layout change |
| R-08 | One unexplained StoreKit test failure | Low (not reproduced in 11 runs) | Test confidence | Open, mitigated | Treat a recurrence as a C04 regression |
| R-02/R-03 | Deletion cut short or failing | Low | Privacy | Fixed in code; device checks open | Section 11, item 3 |
| R-04/R-05 | Compaction on real devices (temporary file, timing, locked iPhone) | Low | Privacy, launch time | Fixed in code; device checks open | Section 11, item 4 |
| R-16 | Keychain guard on a real reinstall | Low | Confusing sign-in state | Fixed in code; signed-build check open | Section 11, item 5 |
| R-09 | Source-scan guard names only variables called `snapshot`; no worst-case snapshot size test | Low | A future reader could skip `effectiveTier`; a snapshot over the cap is dropped silently | Open (unchanged) | Widen the scan; add a worst-case fixture |
| R-10 | One extra complication transfer on the first Premium snapshot | Low | Budget, a few a month | Accepted | None |
| R-19 | Tier and window read in two hops | Low | A briefly mismatched snapshot, self-corrects | Open (unchanged) | Read both in one hop |
| R-11 | Offline cold start cannot show the payment problem | Medium | Message missing offline | Open: owner decision | Persist the state or accept |
| D-1 | Disk-space check not in compaction | Low | A full disk makes `VACUUM` fail cleanly; the request waits | Open: owner decision | Declare the API or keep the 16 MB cap |
| N-1 | Stage 1B is in no backup and not on any remote | Certain | Loss of the work with the Mac | Open | Back up after the owner's review |

Stage 1B is **not complete**: items 5 to 8 of section 8.4 and section 11 are open, and the owner has not reviewed or accepted any condition.

