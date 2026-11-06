# NOCTIS_STAGE1B_INDEPENDENT_REVIEW.md

Review of Stage 1B on `release/stage1b-hardening`, base `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b`. Written 2026-11-02.

**Read-only.** No project file was changed, staged or committed; nothing was reset, cleaned or stashed; the second worktree was not touched (its `git diff --binary` hash is still `83a81df85233c1d2`). The only file this review created is this one. I ran the StoreKit scheme three more times, with build output outside the repository, to look at the first StoreKit failure.

**Independence caveat.** The reviewer is the same agent that wrote the code, working from the diff, the base commit and fresh runs, not from memory of intent. Treat it as a second pass, not as a separate pair of eyes. Findings that rest on Apple behaviour I did not re-check against the Apple pages are marked **[A]**; things only a device, Sandbox account or screenshot can settle are marked **[D]**; things I did not examine are **[N]**.

## Verdict: APPROVED WITH CONDITIONS

No Critical finding. One High (R-01) must be fixed before this is committed. The Medium findings R-02 to R-08 need either a fix or an explicit owner decision to accept them. Everything else can follow the commit.

What I did and did not do:

- Diff read in full against the base: 30 modified files and 10 added files (the 40 in `NOCTIS_STAGE1B_SOURCE_DIFF.patch`), plus both reports.
- Test count verified by counting `@Test` in the new and edited files: 6 + 12 + 7 + 5 + 30 + 4 + 3 = **67 new test functions**, which matches the suite growth (2,646 to 2,713).
- Checks of the Watch complication provider, the iPhone widget provider and the background refresher were made by reading them.
- Not run in this review: the full package suite (ran in the implementation stage: 2,713 passed), UI tests, any screenshot, any device.

## 1. Frontend and UI/UX

User-visible changes in the diff, all of them (compared with the base):

| Change | File | Visible when |
| --- | --- | --- |
| Rule under text-only buttons | `DesignSystem/NoctisButtonShape.swift` (new), applied in `NoctisCTA.swift:127` (`NoctisTextButton`), `OnboardingStepScaffold.swift` (`OnboardingSecondaryButton`), `PaywallScreen.swift` (free-plan link, footer links, Restore), `WindDownScreen.swift` (End) | Only with Button Shapes on |
| Share-card preview ignores Smart Invert | `HomeShare.swift`, `ReviewShare.swift` | Only with Smart Invert on |
| "Payment problem" text and Manage subscription button for a free person in billing retry | `SubscriptionSummary.swift` (detail), `SettingsPages.swift:447` | Only after a failed payment with no grace period |
| Debug flag `-mockSubscription payment` | `AppContainer.swift` | DEBUG only |

With the setting off, the Button Shapes modifier draws nothing (`ButtonShapeTests.withTheSettingOffNothingIsDrawn` proves the pixels equal an unmodified label on the simulator, [V by the implementation stage's run]). I found no change to colours, typography, spacing, navigation or animation outside those places. No other SwiftUI file in the diff touches layout.

### R-06 · Medium · Button Shapes rule may not match the text and is only tested as "different from nothing"
- **Where:** `DesignSystem/NoctisButtonShape.swift:20` (`Rectangle().fill(.foreground)`), call sites such as `NoctisCTA.swift:124-127`.
- **What:** the modifier is attached after `.foregroundStyle(...)`. The rule is an overlay on the result, so it sits outside that style's scope and probably takes the default foreground (black in Light, white in Dark) instead of the text's own tone (ink2, or ivory at 0.65 to 0.7 opacity). Two further risks: on wrapped text the overlay spans the proposed width, so a centred two-line label gets a full-width rule under its last line; and the rule is offset 2 pt below the view, which a clipping container would cut.
- **Evidence:** reading the modifier order; the test checks only that the setting-on image differs from the setting-off image on a black-on-white label [V that it differs; N that the colour or position is right in any real screen].
- **Fix:** put the rule inside the same styled scope (apply `.foregroundStyle` after `.noctisButtonShape()`, or use `.underline(showShapes)` on the `Text`, which handles wrapping and colour); then take the screenshots below.
- **Affects UI/UX:** yes, only with Button Shapes on. No user data.
- **Status: fixed (uncommitted).** The rule was replaced by the text's own underline (`View.underline`), which takes the text's colour and weight and follows each wrapped line. Render tests: off is pixel-identical to no modifier (including wrapped text); on is underlined; a red label has no black pixel; a wrapped label is underlined line by line with nothing below the last line; the size does not change. **Screenshots** (Docs/evidence/stage1b/screenshots): Subscription page, light/dark/AX5, setting off is pixel-identical to the base build below the status bar in all three; on, "Restore purchases" is underlined in its own colour. Paywall: "Restore" and "Continue with the free plan" are underlined; **the footer links (Restore Purchases, Terms, Privacy) were underlined too in the first version, and the screenshots showed the system already draws a grey pill on them with Button Shapes on, so they would have had two decorations: removed.** Not screenshotted: the wind-down End control (the launch flag landed on Home), onboarding secondary buttons, the share sheets.

### R-11 · Low · Payment-problem presentation: coverage and consistency
- **Where:** `SubscriptionSummary.swift` (detail), `SettingsPages.swift:447`, `EntitlementManager.swift:132`, `AppContainer.swift:700` (stale comment).
- **What:** (a) The page headline stays "Free" and the scaffold summary still says "You're on the free plan." above a body that says Premium is paused; other places that show the plan (Profile row) are unchanged. (b) A cold, offline launch cannot show the message: `renewal()` still needs one successful product fetch in the process before the cached group id exists, and that cache is memory only (`EntitlementClient.swift:53`). So P-04's offline goal is only partly met. (c) The flag list comment at `AppContainer.swift:700` does not list `payment`. (d) There is no UI test or screenshot for the new state.
- **Evidence:** reading; `PremiumWindowFromTheStoreTests.aPaymentThatCannotBeTakenIsSaidPlainly` covers the manager and the copy, not the screen.
- **Fix:** screenshot the state with `-mockSubscription payment`; decide whether the headline or scaffold line should change; update the comment. Offline cold start needs either a persisted state (owner decision: new data kept) or acceptance.
- **Affects UI/UX:** yes (one page). No user data.
- **Status: wording made consistent (uncommitted); offline cold start still not covered.** A paused plan now reads "Premium paused" (headline) and "Your payment needs attention." (page line), and the stale comment lists `payment`; the free plan and the premium states read exactly as before (tests). Screenshots: Subscription payment-problem state, light/dark/AX5, base against after (the base build ignores `-mockSubscription payment` and shows the free page). At AX5 the page text is long and the Manage subscription button is below the fold (the page scrolls; same layout rule as every other page). The offline cold-start gap (the group id is cached in memory only) is unchanged: persisting it would add stored data, so it is the owner's decision. Wording remains the owner's to approve.

Screens that need before/after screenshots (setting off must equal the base; setting on is new):

1. Every screen with a `NoctisTextButton` or the five text links, with Button Shapes on and off, light and dark, default size and AX5: Paywall (free-plan link, footer links, Restore), Onboarding secondary buttons ("Skip", "Not now"), Wind-down End (minimal stage), and the Settings and Profile screens that use `NoctisTextButton` (for example Restore purchases, Health data settings).
2. Settings > Subscription in the payment-problem state, light and dark, default size and AX5.
3. Home share sheet and Review share sheet with Smart Invert on and off.
4. The same screens with the setting off, compared pixel for pixel with the base build.

## 2. Premium and StoreKit

Reviewed: `effectiveTier(at:)` and its consumers, the renewal and expiry transitions, the slack, offline, grace, billing retry, restore, and Watch, widget and Siri consistency.

What is correct, by reading and by the passing tests:

- `effectiveTier` (`WidgetSnapshot.swift:401`) is a pure function of the snapshot and a clock; `premiumLockDate` adds the slack only when `autoRenews`. A free snapshot can never carry an end (init clears it), `with(tier:)` clears it.
- Every reader that existed in `NoctisWidgetKit`, `NoctisWatchKit`, `NoctisIntentKit` and `Widgets/Home` now passes a clock. The Watch complication provider builds its input with `now: entry.date` (`Watch/Widgets/NOCTISWatchWidgets.swift:87`) and its timeline from the same builder (`WatchComplicationSchedule.dates`), so the lock entry reaches complications as well as widgets.
- Grace gets no slack (`premiumAutoRenews` is false in grace), offline uses `willAutoRenew ?? true`, restore and renewal go through `refresh()` as before.

### R-01 · High · Background wake awaits the store before it refreshes Health, inside a 20-second budget
- **Where:** `AppRoot/AppContainer.swift:419-425` (the `BackgroundRefresher` closure; `await store.entitlementManager.refresh()` at line 422), `NoctisCore/BackgroundRefresher.swift` (`defaultTimeBudget = 20`).
- **What:** the closure runs the entitlement refresh, then the Home refresh, in sequence, within one 20-second budget. A background wake is a fresh process, so the in-memory subscription-group cache is empty and `renewal()` goes to `Product.products(for:)` first (`EntitlementClient.swift:53`), which can wait on a slow network. The comment at line 421 says "It never holds up the Health refresh"; that is false for this code. A slow or hung product fetch uses the budget the Health refresh needs, so the widgets' overnight update (R46, which had no network step) can time out. After a timeout the completion handler is called and the system may suspend the process mid-refresh.
- **Evidence:** reading both files. Not reproduced under a slow network [D]. `PremiumWiringTests.aBackgroundWakeAsksTheStoreBeforeItRefreshesHome` pins the order, so the test would also have to change.
- **Fix:** run the Home refresh first (or concurrently with `async let`) and give the entitlement call its own short timeout; correct the comment and the test.
- **Affects:** the widgets' and Watch's overnight data (stale numbers). Not stored user data.
- **Status: fixed after this review (uncommitted).** `AppContainer.swift` now refreshes Home first and asks the store afterwards; the comment is corrected. A plan found changed after the Home refresh rewrites the snapshot through `onTierChange` and `onPremiumWindowChange`. `PremiumWiringTests.aBackgroundWakeRefreshesHomeBeforeItAsksTheStore` pins the new order, and the new `aPlanFoundChangedAfterTheHomeRefreshRewritesTheSnapshotItself` runs the order with a fake store against a real publisher. Both pass with `PremiumWiringTests`, `PremiumWindowPublishingTests`, `PremiumWindowFromTheStoreTests`, `BackgroundRefreshTests` and `TierPublishingTests` (16 tests). Not re-run: the full suite and the Release build. Not verified under a slow network [D].

### R-07 · Medium · The 48-hour slack makes widgets, Watch and Siri disagree with the app, and some changes are not seen at all while the app is closed
- **Where:** `WidgetSnapshot.swift:334` (`renewalSlack`), `EntitlementManager.swift` (`premiumAutoRenews`).
- **What:** when a payment fails and there is no grace period, the app locks at the end date as soon as it runs, but a snapshot written earlier says `autoRenews: true`, so widgets, complications, Siri and the Watch stay Premium for up to 48 hours past the end if the app does not run. A cancellation, a refund or a revocation made while the app is closed is not known to those surfaces until the app runs (the store announces changes only to a running process); a cancelled plan keeps the slack it had when the snapshot was written. Each is bounded, but it is a real inconsistency between surfaces, and 48 hours is the plan's proposal, not a measured figure.
- **Evidence:** reading `EntitlementManager.refresh()` and the publisher; `EffectiveTierTests` prove the arithmetic, not the real-world renewal timing [A][D].
- **Fix:** none needed in code if the owner accepts it; the owner decision (slack length) and the Sandbox check of a late renewal [D] should be recorded before release. If the owner wants less drift, shorten the slack, or drop it for plans whose last refresh is older than a threshold.
- **Affects:** what a lapsed person sees outside the app for up to 48 hours. No user data.

### R-08 · Medium · The first StoreKit failure is unexplained, and its evidence was lost
- **Where:** `Tests/StoreTests/StoreKitSessionTests.swift:53` (`Rig.product`), my first `NOCTIS-Store` run.
- **What:** on my tree's first run every test that buys a plan failed with `store.products.first { $0.id == id }` empty at `StoreKitSessionTests.swift:55`. Later runs passed.
- **Investigation:**
  - The base commit, run on a clean copy, passed first time (24 tests, 1 known issue).
  - My tree passed on runs 2 and 3 in the implementation stage, and on three more runs in this review: five consecutive passes, 24 of 24 each time, all with the known issue.
  - `StoreManager.swift` is not in the diff, so the code that loads products is unchanged. The one StoreKit-client change is in `renewal()`.
  - The test helper calls `store.loadProducts()` exactly once, with no retry, right after creating an `SKTestSession`; an empty answer from a cold StoreKit test daemon fails the test.
  - The first-run log was overwritten by my own script (it truncated `store.log` on each run), so the failing run's detail cannot be recovered.
- **Conclusion:** I cannot show it is unrelated to the diff and I cannot reproduce it. Evidence points to a cold-start problem in the test environment (a fresh derived-data folder just after a killed test run and a Release build) rather than to the change, but that is an inference.
- **Fix:** keep the run logs (do not truncate); make `Rig.product` retry `loadProducts()` a few times; if a failure recurs on a clean machine, treat it as a regression of C04 until shown otherwise.
- **Affects:** the reliability of the only automated StoreKit evidence. No UI or user data.
- **Status: investigated, not explained; mitigated (uncommitted).** All logs are now kept in `Docs/evidence/stage1b/` (the first full run, the three probe runs, the base-commit run, three final runs, the final full suite). The first-run failure log itself was lost to my own truncation and cannot be recovered; no later run failed (5 earlier passes, 3 more in the corrective pass, 24 of 24 each, 1 known issue). `StoreManager.swift` is unchanged. The test helper now asks for the products up to five times before failing. If a failure recurs, treat it as a C04 regression until shown otherwise.

Not covered by any test, for the record (the plan listed them): the resolver's family-shared branch (scenario 13), a direct revoked case (scenario 10), and the real billing-retry state through the screen.

## 3. Data safety

### R-02 · Medium · An interrupted delete-all is only resumed when a screen appears
- **Where:** `App/NoctisApp.swift:54` (`.task(id: container.generation)` on the root view), `AppContainer.swift:417` (`isOnboarded: { model.profile.onboardingComplete }`).
- **What:** `NoctisApp.init` builds the container with no scene on background launches (a Health wake, an intent, the Sleep sounds control), and the resume is attached to the view, so it does not run then. If the profile was not yet removed when the app was cut off (the early steps are the reminder, audio, wind-down and alarm steps, before the stores), the background refresher still sees an onboarded, authorized person and refreshes Home, which republishes the widget snapshot and sends the Watch fresh numbers. Deleted-looking data reappears on the widgets and the Watch until the person opens the app.
- **Evidence:** reading `NoctisApp.swift`, `BackgroundRefresher` and the step order in `DataWiring.deleteAllSteps`. Not reproduced [D: kill mid delete-all].
- **Fix:** make the refresher's `isOnboarded` (or a new gate) false while `dataManager.hasInterruptedDeletion`, and run the resume from container creation, not from a view task.
- **Affects:** user-data privacy on widgets and the Watch after an interruption. Not UI.
- **Status: fixed after this review (uncommitted).** `AppContainer` now starts the resume when the container is made (once per process, `interruptedDeletion`), so a background launch finishes it too; `NoctisApp` waits for that task and then restarts the app. The background refresher and the Watch's update request do nothing while `DataManager.hasPendingDeleteAll()` is true. Tests: `DeleteAllResumeTests.theBackgroundWorkStopsWhileADeletionIsUnfinished` and the container-start check (both are source and logic checks). **Verified on the simulator in the corrective pass:** with the marker set (passed as a launch argument), a launch with no root view (`-intentRunner`) started the resume from container creation about half a second after init and ran all 47 steps with no failure in about 0.2 s; a normal foreground launch resumed once and restarted the container once, with no second resume (`Docs/evidence/stage1b/resume-simulator-log.txt`, from a throwaway instrumented copy outside the repository). Not verified: a real kill mid-run, and a real Health wake [D].

### R-03 · Medium · A failed deletion step can leave data behind with no report
- **Where:** `NoctisCore/DataManager.swift:207` (`resumeInterruptedDeletion`), `AppRoot/DataWiring.swift:235` (`try? FileManager.default.removeItem`).
- **What:** (a) The resume runs the list once and clears the marker whatever the result (by design, to avoid a loop), and shows nothing: a step that fails twice leaves data and no one is told. (b) The "Removing database files" step swallows each file removal error with `try?`, so a database file that cannot be removed is not a failed step at all: the deletion reports success, the marker is cleared and the file stays. This part of (b) predates Stage 1B, but the resume now relies on "succeeded". (c) The runner continues after a failed step, so an early failure does not stop the rest, which is right, but it is also what makes partial states possible.
- **Evidence:** reading. `DeleteAllResumeTests` cover the marker logic with steps that throw; none covers a step that "succeeds" without deleting.
- **Fix:** make the files step throw when a removal fails (collect the errors); on resume, if the report still has failures, keep a marker value that makes the app show the existing failure state once (or at least log the step ids, which hold no personal data).
- **Affects:** user data (deletion completeness). Not UI, except the new message.
- **Status: fixed (uncommitted), strengthened in the corrective pass.** The "Removing database files" step throws `FilesNotRemoved` when a removal fails (a file already gone does not count), so it is a failed step in the sheet and keeps the marker. The marker counts attempts: a resume that still fails keeps it for the next launch, three launches in all. **After the third, the marker is no longer simply cleared: the failing step ids are written to `noctis.deleteAll.unfinished`, which survives relaunch, and Data management shows a "NEEDS ATTENTION" card naming the steps and pointing at "Delete all NOCTIS data" to try again; a delete-all that works clears the record.** `DataWiring` now passes its defaults to `DataManager` (also R-20). Tests: `DeleteAllFileFailureTests` (a real immutable database file through the real wiring), the bounded-attempts test, the persistence and relaunch tests, the notice-copy test. The card was not screenshotted [N].

### R-04 · Medium · `VACUUM` writes a temporary copy of the kept rows outside the protected folder [A]
- **Where:** `NoctisCore/StoreCompaction.swift:75-77`.
- **What:** SQLite builds the compacted database in a temporary file; on iOS that is the app's `tmp` directory, which does not carry the Journal and Coach folders' `complete` protection class, and it holds the rows that were kept. It is removed afterwards. This is the Journal and Coach text, transiently, at a weaker class than the stores themselves.
- **Evidence:** reading, plus SQLite's documented behaviour [A]; I did not watch a temp file appear [N].
- **Fix:** run `PRAGMA temp_store = MEMORY;` before `VACUUM` (the file is capped at 32 MB, so memory is enough).
- **Affects:** privacy of Journal and Coach content during a rare operation.
- **Status: confirmed by measurement and fixed (uncommitted).** On the Mac's system SQLite (3.54, `TEMP_STORE=1`), `VACUUM` of a 470 MB database opened a temporary file `etilqs_…` in the process's temporary folder (seen with `lsof`) and held the whole copy; with `PRAGMA temp_store = MEMORY` no temporary file handle appeared and resident memory rose by about the database size (633 MB against 186 MB). On the iOS Simulator's SQLite, inside the test process, a 30 MB database showed the temporary file during the default `VACUUM` (the positive control) and none during `StoreCompaction.compact`. `compact` now sets `temp_store = MEMORY` first and the cap is 16 MB, so the memory it uses is bounded. Journal and Coach store folders keep their protection class and backup exclusion through compaction (compared before and after in `StoreCompactionRealStoreTests`; the simulator reports the attributes it was given). Not measured on a device [D]. Privacy manifests: **not changed**; see the note in R-05 about the disk-space API.

### R-05 · Medium · Compaction was proven on a synthetic table, not on a real SwiftData store, and it runs on the main thread before the first frame
- **Where:** `StoreCompactionTests.swift` (builds its own `entry` table), `AppContainer.swift:80`, `StoreCompaction.swift:59-77`.
- **What:** no test compacts a store made by `NoctisStore.container`, `JournalContainer.make` or `CoachHistoryContainer.make`, then reopens it through the container and reads the rows; and none checks that file protection and the backup-exclusion flag survive the operation (they should, since it works in place, but that is unverified). It also runs synchronously during `AppContainer.init`, up to a quick check of 64 MB and a `VACUUM` of 32 MB, before the first frame; this happens only after a deletion, but it counts against the launch budget.
- **Evidence:** reading the tests and the call site; `StoreCompactionTests` all pass (12) [V].
- **Fix:** add one test per real store (insert, delete, compact, reopen via the container, fetch); move the work off the first-frame path or accept it with a measured launch time.
- **Affects:** user data integrity (low likelihood) and launch time.
- **Status: tested and measured (uncommitted).** `StoreCompactionRealStoreTests` insert, delete, compact, reopen through `JournalContainer`, `CoachHistoryContainer` and `NoctisStore.container`, and check every kept row, no store set aside, protection and backup attributes unchanged, and that the app database still saves. Measured on the Mac simulator (not a device): Journal 12.2 MB to 1.4 MB in 16 ms; Coach 2.3 MB to 1.8 MB in 15 ms; app database 3.0 MB to 2.5 MB in 21 ms. A launch with no request is one flag read (about 1 ms): the list of database files is no longer built unless a request is pending. **Justification for compacting before the first frame:** it must run before any store opens, it runs only once after a deletion of one kind of data, the stores are small (tens of milliseconds measured), and the cap is 16 MB. Device timing is still to be measured [D]. The disk-space check promised in the plan was dropped (it needs a privacy-manifest declaration); the 16 MB cap bounds the damage of a full disk instead. If the owner prefers the check, declare `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` in the app manifest: the owner's decision.

### R-16 · Low · `FreshInstallGuard` spends its one chance even if the Keychain cannot be read
- **Where:** `NoctisCore/Account/FreshInstallGuard.swift` (`run()`).
- **What:** `keychain.read()` returns nil before the first unlock after a restart; the guard then sets the marker and never clears a stale item. A fresh install is user-launched and unlocked, so this is very unlikely; I note it because the marker is set unconditionally.
- **Fix:** set the marker only after a successful read (or a definite "not found").
- **Affects:** only the edge where a stale sign-in survives a reinstall. No other user data.
- **Status: fixed (uncommitted).** The Keychain now answers found, not found or unavailable (`KeychainLookup`); `errSecItemNotFound` is not found and any other status (for example before the first unlock) is unavailable. When unavailable, the guard clears nothing and records nothing, so the next launch asks again. Tests added. Note from the simulator run: the ad-hoc-signed Debug build has no Keychain entitlement, so there the lookup is always unavailable; the real behaviour needs a signed build on a device [D].

Reviewed and found sound: the guard needs both conditions (no marker and no `default.store`) before it deletes anything, so an update, an offloaded app or a restore keeps the sign-in; the Keychain item is `ThisDeviceOnly` (`AccountStore.swift`), which is why a restore to a new device is signed out; compaction refuses damaged and oversize files, never runs unless a deletion asked, keeps its request when the file is busy or locked, and the `VACUUM` is transactional [A]; the delete-all marker is under the `noctis.` prefix and removed by the preferences step; the new keys are in the inventory and its tests pass.

### R-12 · Low · Documentation inaccuracies
- `Docs/MIGRATION_PROCEDURE.md` step 3 refers to `NoctisCurrentSchema` "and the equivalents"; only the app database has such an alias (`NoctisSchema.swift:27`); Coach and Journal use `CoachHistorySchemaV1` and `JournalSchemaV1` directly.
- `Docs/PRIVACY_REPORT.md:107` (proposed wording) says the wake alarm "comes with" a backup restore. The alarm's settings row does; the system alarm is scheduled through AlarmKit and is not restored by a backup [A]. The wording is the owner's to approve, so correct it before approval.
- The new-phone wording and the inventory text say the snapshot holds the end date and renewal flag, but `Docs/site/privacy.html` and the store listing were not checked for a statement about what the widget file holds [N].
- Backup and migration documentation otherwise match the code: Journal, Coach, insights and cached summaries are excluded from backup (`JournalStore.swift:71`, `CoachHistory.swift:258`, `InsightStore.swift:54`, `HomeSnapshotStore.swift:79`), the sign-in item is device-only, and the three database folders are as documented.
- **Affects:** documentation only (one item affects what the owner may promise users).
- **Status: corrected (uncommitted).** `MIGRATION_PROCEDURE.md` step 3 names the three places the current schema is chosen; the proposed new-phone wording now says the alarm's settings come back and the system alarm is set up again when NOCTIS opens. `Docs/site/privacy.html` says the widgets and the Watch show "a short summary of your recovery and sleep"; it does not mention the plan end, and the owner should decide whether it should.

## 4. Watch and widgets

- **Snapshot consistency.** Equal-epoch snapshots are accepted by `WatchInbox` when `generatedAt` is not older (`WatchInbox.swift`, `snapshot.generatedAt < generated` rejects only strictly older), so a tier-only republish in the same second is accepted [V by reading]. The publisher's same-content check includes the new fields, so a renewal or cancellation writes.
- **Expiry propagation.** Widgets: the timeline holds an entry at the lock moment when it falls inside the 12-hour horizon; beyond it the reload at the horizon looks again [V by reading; test `ExpiryTimelineTests`]. Watch: the same builder and `input.now = entry.date`. Siri: `IntentEnvironment.tier()` uses the clock. All consistent with one another.
- **Duplicate or delayed messages.** Unchanged ordering rules (epoch, then `generatedAt`). A delayed older context is ignored; a duplicate is idempotent.
- **Complication updates.** One extra wake on a plan change (`WatchSyncService.swift:178-179`), within the existing budget and enabled flag, not marked when the budget is zero. A mark written before this change has two parts and never wakes on a plan change (intended).

### R-10 · Low · Complication wake side effects
- **Where:** `WatchSyncService.swift:171-182`.
- **What:** on a cold start where the first snapshot is Premium without an end (the store has not answered) and the next one has it, the plan token changes and spends one extra complication transfer. The publisher mitigates the common case by carrying the written end forward, so this appears only on the very first Premium snapshot. Budget impact is a few transfers a month.
- **Fix:** none needed; record it.

### R-19 · Low · Tier and window are read in two separate hops
- **Where:** `WidgetPublisher.swift` (`current()`), `AppContainer.swift` (`setTier` and `setPremiumWindow` closures).
- **What:** the tier and the window are read through two `MainActor.run` calls. A change between them can produce a snapshot that pairs one with the other's old value. `onTierChange` and `onPremiumWindowChange` each republish, so the next write corrects it; the window is only briefly wrong.
- **Fix:** read both in one hop.

### Physical-device verification required (none of this was or can be done on a simulator)

1. A real plan end with the app closed: the Medium and Large widgets, the Lock Screen widgets and the Watch complications flip to the locked state at the lock moment, with no app launch.
2. A renewal that completes late (after the end date, before the slack ends): nothing locks.
3. A cancellation, a refund and a revoked plan while the app is closed: how long each takes to show on widgets, Watch and Siri.
4. A Shortcut or Siri request after the plan ends, with the app closed.
5. A Health wake with a slow or no network (R-01): does Home still refresh inside the budget?
6. Watch complication refresh after a purchase or lapse: whether the transfer arrives, the remaining-budget log, and the face with the Watch app closed.
7. Delete-all killed at several steps, then a background launch and a foreground launch (R-02, R-03): what the widgets, the Watch and the screens show.
8. Compaction on a real device store after deleting Journal entries (R-04, R-05), with the iPhone locked at launch.
9. A real reinstall: the Keychain sign-in is gone; an app update and an offloaded app keep it (R-16).
10. The Watch Dock and app-switcher snapshot (S1B-D03, still open).

## 5. Accessibility

### R-14 · Medium · Most of the Tier C settings are still unsupported or unverified
- **Where:** the whole app; the implementation covered `NoctisButtonShape.swift` and two `accessibilityIgnoresInvertColors` calls.
- **What:** I checked complete sets, not samples, where the question allows it:
  - **Smart Invert:** the only code that shows a bitmap is `Image(uiImage:)` in `HomeShare.swift` and `ReviewShare.swift` (a full search of `Packages`, `App`, `Widgets` and `Watch` found no other `Image(uiImage:)`, `UIImage(` outside the share renderer, or asset `Image("…")`), and both now opt out. Complete for bitmaps. Everything else is SwiftUI chrome that Smart Invert inverts by design; whether the dark UI looks acceptable inverted is unverified [D].
  - **Button Shapes:** only the text-only buttons listed in section 1 got the rule. The app has about 77 `.plain` buttons; I did not classify all of them in this review, and the implementation classified the text-only ones from a heuristic (one `Text`, no image or background). Custom icon-only buttons (back buttons, `NightIconButton`, close buttons) get no shape: with the setting on they look unchanged. Whether that is acceptable is a design call. Incomplete.
  - **Differentiate Without Color, Bold Text, Increase Contrast, Reduce Transparency, On/Off Labels:** no shipped code reads them except the QA probe; the implementation did not change them and did not run them [N]. UX-03 is therefore still open for these. The earlier sample of "no colour-only meaning found" covered a few files and must not be read as a result.
  - **Reduce Motion:** read in 108 places (source count only; behaviour not run).
- **Fix:** the verification pass below; code only for what it reproduces.
- **Affects:** UI/UX for people using those settings. No user data.

Required accessibility tests (none was run in this stage):

1. **VoiceOver traversal** (the written test, and by hand) on: onboarding, Home, Sleep, Recovery, Insights, Coach, Tonight, wind-down, alarm, Sounds, Settings, Subscription (all states including payment problem), Paywall, share sheets, the privacy cover, and the Watch pages. Check the Button Shapes rule is not announced (`accessibilityHidden` is set), focus lands on sheets and returns, and the payment-problem text is read with its button.
2. **Dynamic Type** at the default, AX3 and AX5 on an SE-sized and a Pro Max-sized simulator, for every screen above and every widget family, with Button Shapes on and off (the rule must not clip or collide with the 44 pt targets).
3. **Display settings**, each on its own and with Dark: Bold Text, Increase Contrast, Reduce Transparency, Differentiate Without Color, On/Off Labels, Button Shapes, Smart Invert, Reduce Motion; screenshots viewed, not just captured.
4. **Touch targets** under Accessibility Inspector, and the 44 pt rule for the new `Restore`, `End` and footer links.
5. **Contrast**: the existing ratio tests, plus a check that the increased-contrast variants are asserted (not confirmed).

## 6. Test quality

The 67 new tests, by what they prove:

| Group | Count | Kind |
| --- | --- | --- |
| `EffectiveTierTests`, `PremiumEndCodingTests`, `ExpiryTimelineTests`, `ExpirySurfaceTests`, `PremiumWindowPublishingTests`, `PremiumWindowFromTheStoreTests`, three `WatchSyncServiceTests` additions | 28 + 3 | behaviour, simulator [V] |
| `SnapshotTierReadersTests`, `PremiumWiringTests`, the app-wiring tests in `DeleteAllResumeTests`, `FreshInstallGuardTests`, `StoreCompactionRequestTests`, `ButtonShapeTests` | about 9 | **source inspection** (substring or pattern scans of source files) |
| `FreshInstallGuardTests`, `DeleteAllResumeTests`, `StoreCompactionTests`, `StoreCompactionRequestTests`, `SchemaFingerprintTests` (rest) | about 27 | behaviour or shape, simulator [V] |
| `ButtonShapeTests` render, `SmartInvertTests` | 3 | render comparison and source scan |

None is real-device verification.

### R-09 · Low · Several guards are narrower than they look
- **`SnapshotTierReadersTests`** (`PremiumExpiryTests.swift:211`): the pattern is `snapshot\??\.tier`, so it catches only a variable named exactly `snapshot`. A reader that binds the snapshot to another name (`let value = …; value.tier`) passes. Other uses of `.tier` on snapshots exist only in writers today, but the test does not enforce what its name says. **Fix:** also scan for `\.tier\b` on any `WidgetSnapshot` in the guarded folders, with an allow-list of the writers.
- **Size headroom** (`PremiumExpiryTests.swift:106`): the test checks one fixture is under half the cap. The plan's worst-case snapshot (full factors, alarm, recovery factors, longest names) was not measured, and an over-size snapshot is dropped silently on both write and receive (`WidgetSnapshotStore`, `WatchInbox`). The two new keys add about 30 bytes, so I expect headroom, but it is not shown [N]. **Fix:** a worst-case fixture test.
- **`ButtonShapeTests.theTextButtonAndTheTextLinksUseIt`** counts the substring `.noctisButtonShape()` per file, which a comment or a wrong call site would satisfy.
- **`StoreCompactionTests.aFileThatCannotBeOpenedForWritingWaitsForTheNextLaunch`** accepts `.unavailable` or `.failed`.
- Source-scan tests of `AppContainer.swift` (`PremiumWiringTests`, the guard-before-account and compaction-before-open checks) pin text order, not behaviour; a refactor that keeps the text can still break the order.

### Untested failure paths
- A delete-all step that "succeeds" without deleting (R-03); a real kill at each step with the real step list; a background launch with the marker set (R-02).
- `VACUUM` on a real SwiftData store and its file attributes (R-05); a full disk; a locked iPhone at launch.
- A slow or failing `Product.products` in a background wake (R-01); the group cache in the real StoreKit client (only `NOCTIS-Store` touches it).
- The payment-problem screen; Button Shapes in context.
- The resolver's family-shared branch and a direct revoked case.

### R-20 · Low · Test hygiene (fixed with R-03)
- `DataWiring.swift:120` builds `DataManager` without passing `i.defaults`, so existing integration tests (`DataManagementIntegrationTests`, including the failing-journal case) run against the real standard defaults: a failed step leaves `noctis.deleteAll.pending` and a compaction request in the test host's defaults, which persist across runs. Production uses the same defaults, so there is no product impact. **Fix:** pass `i.defaults`.

### Flaky or inconsistent tests
- One failure in the first `NOCTIS-Store` run, not reproduced in five reruns (R-08). The first full-suite run in the implementation stage had two failures that were real consequences of the change (the snapshot-key allow-list and an undeclared required-reason API); both were fixed and the suite then passed. `xcodebuild` also hangs after a run that has failures; that is a tooling property seen three times and not a test fault, and the helper script I used kills it.

### Source, simulator and device, stated plainly
- **Source inspection only:** the wiring and order checks above; the UI claims in section 1 about colours, spacing, layout and animation unchanged (diff reading, plus the pixel-equality test for Button Shapes off).
- **Simulator verified in the implementation stage:** the full package suite (2,713), the Release build (0 warnings), the symbol check (0 hits), `NOCTIS-Store` (24 of 24, after the failed first run). I re-ran only `NOCTIS-Store` in this review.
- **Real device or Sandbox:** nothing.

## 6b. Findings added in the corrective pass

### R-21 · Medium · With Button Shapes on, the Paywall footer links overlap each other and the medical notice (pre-existing)
- **Where:** `OnboardingFeature/PaywallScreen.swift` (`linkLabel`, `links`: the footer is built with negative padding around system `Button` and `Link` views).
- **What:** with Button Shapes on, the system draws a grey pill behind each footer link. At the default size the pills overlap the medical notice below them; at AX5 they overlap each other and the "Privacy" link is hidden. The base build does the same: the screenshots are `paywall_base_*_shapes1.png` and `paywall_base_light-AX5_shapes1.png`. It is not caused by Stage 1B and was not changed.
- **Fix (not done):** lay the footer out without the negative-padding trick when Button Shapes is on, or give the links a fixed height and spacing. This changes the Paywall layout, so it needs the owner's approval.
- **Affects UI/UX:** yes, for people who use Button Shapes. No user data.

### R-22 · Info · A preference file edited from outside is not seen by the app on the simulator
- Writing a key into the app's container with `defaults write <path>` did not reach the running app (nor after a simulator reboot); the app saw the key only as a launch argument. The first resume checks were wrong because of this and were redone with the launch argument and an instrumented copy. Recorded so the next check does not repeat the mistake.

## 7. Findings summary

| ID | Severity | Area | Short |
| --- | --- | --- | --- |
| R-01 | High | Premium / background | Entitlement call sat before Health refresh inside the 20 s wake budget; comment claimed otherwise. **Fixed after the review, narrow tests pass** |
| R-02 | Medium | Data / Watch | Delete-all resume only on a screen; background launches repopulate widgets and Watch. **Fixed; resume shown to run with and without the root view on the simulator** |
| R-03 | Medium | Data | Failed deletion steps can leave data with no report (`try?` in the files step, resume clears marker). **Fixed; a final give-up is now a persistent record with a notice in Data management** |
| R-04 | Medium | Data / privacy | `VACUUM` temp copy of kept rows outside the protected folder. **Confirmed by measurement; fixed with `temp_store = MEMORY`** |
| R-05 | Medium | Data | Compaction untested on real stores; runs on the main thread before first frame. **Tested on real stores, measured (device timing open)** |
| R-06 | Medium | UI | Button Shapes rule colour, width and clipping unverified. **Fixed (text's own underline); screenshots taken** |
| R-07 | Medium | Premium | 48 h slack: surfaces disagree with the app; changes while closed unseen. **Open: owner decision, see the implementation report** |
| R-08 | Medium | Tests | First StoreKit failure unexplained, evidence lost. **Still unexplained; logs now kept; helper retries** |
| R-14 | Medium | Accessibility | Most Tier C settings unsupported or unverified. **Still open on purpose; matrix in `Docs/ACCESSIBILITY_TEST_MATRIX.md`** |
| R-09 | Low | Tests | Source-scan and size guards narrower than their names |
| R-10 | Low | Watch | One extra complication transfer on first Premium snapshot |
| R-11 | Low | UI | Payment-problem screen coverage; offline cold start cannot show it. **Wording made consistent; screenshots taken; offline cold start open** |
| R-12 | Low | Docs | Migration doc alias, alarm-restore wording. **Corrected** |
| R-16 | Low | Data | Keychain guard sets marker without a successful read. **Fixed** |
| R-19 | Low | Premium | Tier and window read in two hops |
| R-20 | Low | Tests | `DataManager` defaults not injected in the wiring. **Fixed with R-03** |
| R-21 | Medium | UI (pre-existing) | Paywall footer links overlap with Button Shapes on, in the base build too. **Not changed; owner decision** |
| R-22 | Info | Method | Preference files edited from outside are not seen by the app on the simulator |

## 8. Conditions for approval

Status after the corrective pass (the verdict stays **APPROVED WITH CONDITIONS**; Stage 1B is not declared complete):

| # | Condition | Status |
| --- | --- | --- |
| 1 | Fix R-01 | Fixed; order pinned by tests; failure and timeout paths tested (`WakeBudgetTests`) |
| 2 | Decide R-02 and R-03 | Fixed; background-launch resume verified on the simulator; persistent failure record and notice added |
| 3 | Apply R-04, add the real-store compaction test (R-05) | Done, with measurements; device timing still open |
| 4 | Screenshot and decide R-06 | Fixed and screenshotted; two surfaces not captured (wind-down End, onboarding secondary buttons) |
| 5 | Owner decisions (slack, wording, new-phone wording, Family Sharing) | **Open, none assumed**; R-21 and the disk-space declaration added to the list |
| 6 | Keep the StoreKit logs, retry the product load, rerun on the final tree | Done: logs kept, helper retries, three more clean runs; the first failure is still unexplained |
| 7 | Record that R-14 leaves UX-03 open and run the accessibility tests | **Open on purpose**; matrix written; tests not run |

Nothing here has been committed or pushed.
