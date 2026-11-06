# NOCTIS_STAGE1B_IMPLEMENTATION_PLAN.md

Stage 1B, Phase 1: technical discovery and implementation plan. Written 2026-11-02.

**This phase changed nothing in the project.** No source, test, configuration, documentation or project file was edited. No branch, commit, push, stash, reset or checkout was made. The second worktree was not touched. The only file created is this plan. Nothing has been implemented. Implementation waits for the owner's approval of this plan.

How to read the evidence labels used throughout:

- **[V]** verified by reading the source or tests in this repository during this phase.
- **[R]** reported by a repository document (ledger, audit, report). I did not re-run it.
- **[A]** Apple behaviour I am stating from knowledge or from secondary sources. The two Apple documentation pages I tried to fetch (`updateApplicationContext(_:)` and `privacySensitive(_:)`) returned only their titles, and my web searches returned forum and WWDC material, not authoritative page text. Every [A] item must be re-checked against the current Apple documentation, or on a device, before code depends on it.
- **[D]** can only be settled on a physical device, a real Sandbox or TestFlight account, or a real App Store expiry.
- **[N]** not verified in this phase.

---

## 1. Executive summary

Stage 1A is committed and intact. Stage 1B targets the four areas that remain after it: accessibility (UX-01, UX-02, UX-03, X-27), data reliability (X-11, X-15, X-16), subscription reliability (P-03, P-04, P-05, P-07, X-09) and Apple Watch behaviour.

What matters most:

1. **The plan-expiry gap (P-03 / X-09) is real, and the fix is small and safe.** Widgets, complications, Siri and the Watch decide Premium from a single Boolean-like `tier` in the snapshot file [V]. Nothing re-evaluates it until the app runs. The fix is to carry the access end date in the snapshot and compute the tier through one function that takes the current time. The same function also drives a timeline entry that flips the widget at the right moment. It needs no server and no StoreKit in extensions. It needs one owner choice (how much grace to give an auto-renewing plan, section 13).
2. **UX-03 is smaller than the audit's wording, but real.** Bold Text is mostly handled by the system. The genuine code gaps are Button Shapes (plain-style buttons), Differentiate Without Color (colour-coded states need a text or shape twin) and Smart Invert (share-card bitmaps). Reduce Motion is already widely handled (108 reads) [V]. The 18 to 26 open layout rows are all "fixed in source, not re-photographed" [R], so they need a verification pass, not code.
3. **The data-reliability items are mostly "document and add a guard", not "build".** Migration machinery already exists and is tested with synthetic versions [V]; there is no real V2 and none should be invented. Interrupted delete-all has no persisted progress [V]; a small resume marker fixes it. SQLite free pages are never compacted [V]; a guarded compaction on the next launch is the smallest safe step. The Keychain item survives uninstall [V]; a first-launch marker fixes it, and it must ship in 1.0 or it becomes a sign-out for existing users.
4. **The Watch design is sound on ordering and deletion, with two gaps.** The deletion epoch and generated-at ordering handle duplicates, old transfers and deletion while disconnected [V]. Gaps: the complication wake ignores tier changes (it fires only on day change or first recovery of the day) [V], and the Watch app has no cover for app-switcher or Dock snapshots (whether it needs one is a device question [D]).
5. **P-04 is mostly presentation.** Billing retry without a grace period already ends Premium in the rules and is covered by a StoreKitTest [V]. What is missing is the message to the person ("payment problem"), and a cheaper, offline-aware status read.
6. **Family Sharing (P-05) is an owner decision and stays off.** Code supports family-shared ownership; the StoreKit configuration says `familyShareable: false` [V]. Nothing in this plan enables it.

Recommended order: subscription expiry first (highest user and revenue impact, smallest risk), then data-reliability guards, then accessibility code, then Watch gaps, then one consolidated device and Sandbox verification pass. Section 15 gives the final recommendation.

---

## 2. Current repository state

Pre-flight results, all read from the live repository during this phase.

| Item | Value |
| --- | --- |
| Repository root | `/Users/sendiwkithnada/Documents/Noctis` |
| Branch | `release/prelaunch-hardening` |
| HEAD | `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b` (`feat: harden NOCTIS pre-launch privacy and HealthKit flows`), matches the expected value [V] |
| Tracked changes | none modified, none staged [V] |
| Untracked files | 8, all reports or the patch: `APP_STORE_PRE_LAUNCH_AUDIT.md`, `NOCTIS_BACKUP_REPORT.md`, `NOCTIS_POST_STAGE1A_BACKUP_REPORT.md`, `NOCTIS_STAGE1A_FINALIZATION_REPORT.md`, `NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md`, `NOCTIS_STAGE1A_REVIEW_REPORT.md`, `NOCTIS_STAGE1A_SECOND_REVIEW_REPORT.md`, `NOCTIS_STAGE1A_SOURCE_DIFF.patch` (this plan will be the ninth) [V] |
| Stage 1A integrity | the committed tree equals the approved patch applied to its parent (checked in the finalization stage [R]; the HEAD hash is unchanged since) |
| Other worktree | `.claude/worktrees/charming-liskov-749f7b`, branch `claude/charming-liskov-749f7b` at `f6fb3c8`, six uncommitted files; the hash of its `git diff --binary` was `83a81df85233c1d2` at the start of this phase, matching the backups [V]. It was not touched. |
| Remote | none; nothing has ever been pushed |
| Backups | original (933 files) and post-Stage-1A (946 files, contains `2b4e7c8`) under `~/Backups/NOCTIS/`; the owner reports a private MEGA copy of the post-1A backup |

Two points the plan depends on:

- Stage 1B work must start from this HEAD on a new branch (proposed `release/stage1b-hardening`), created only after approval.
- The second worktree edits `HomeViewModel.swift`, `RecoveryScreen.swift` and `APP_RULES.md`. Stage 1B does not need those files, so there should be no conflict. If implementation turns out to need one of them, that is a stop-and-ask, not a merge.

---

## 3. Stage 1B scope

In scope: accessibility and UI (Track A), database and data reliability (Track B), StoreKit and subscription reliability (Track C), Apple Watch reliability and privacy (Track D), and the cross-platform data path between them.

Out of scope, as the brief states: backend, Firebase, analytics SDKs, remote AI, cloud sync, new packages, visual redesign, pricing or product changes, deployment changes, unapproved features. The local-first architecture, the SwiftUI design system and the NOCTIS identity stay as they are.

Proposed sub-stages (each is a separate commit set, built and tested before the next):

| Sub-stage | Content | Needs device or Sandbox to finish? |
| --- | --- | --- |
| 1B-1 | Subscription state: expiry-aware tier seam, snapshot expiry metadata, timeline lock entry, background entitlement refresh, billing-problem copy, Watch and complication follow-through | Partly: real expiry and Sandbox [D] |
| 1B-2 | Data reliability: Keychain first-launch marker, interrupted-delete resume, guarded compaction, schema fingerprint test and migration procedure, backup/restore wording | Partly: kill mid-delete on device [D] |
| 1B-3 | Accessibility code: Button Shapes, Differentiate Without Color, Smart Invert, targeted fixes found by the inventory | Needs simulator and device pass |
| 1B-4 | Watch gaps that remain after 1B-1: Dock/app-switcher privacy (only if the device pass shows exposure), stale-data wording | Needs a paired Watch [D] |
| 1B-5 | Consolidated verification pass: AX layout re-shoot, VoiceOver traversal, Tier C settings, Sandbox scenarios, Watch device pass; ledger and docs updated | Yes |

Sub-stages 1B-1 to 1B-4 are independent enough to be reviewed separately. 1B-5 is the only one that produces evidence for the open "unverified" rows.

---

## 4. Accessibility findings and fixes (Track A)

### 4.1 What the source shows

Counts of accessibility environment reads in shipped code (tests excluded), measured this phase [V]:

| Environment value | Reads in shipped code | Where it matters |
| --- | --- | --- |
| `accessibilityReduceMotion` | 108 | animations; broadly handled |
| `colorSchemeContrast` | 8 | Increase Contrast variants |
| `accessibilityShowButtonShapes` | 1, in `AppRoot/EnvironmentProbe.swift` only (a QA probe) | UX-02 |
| `accessibilityDifferentiateWithoutColor` | 1, same probe only | UX-02, UX-03 |
| `legibilityWeight` | 1, same probe only | UX-03 |
| `accessibilityReduceTransparency` | 1, same probe only | UX-03 |
| `accessibilityInvertColors` | 1, same probe only | UX-02 |
| `accessibilityIgnoresInvertColors` | 0 | Smart Invert |

Other facts [V]: the app contains about 77 `.plain`-style buttons plus the custom `NoctisTextButton`; there is one `glassEffect`; contrast ratios are unit-tested for bands, the app palette, paper and welcome surfaces (`BandStyleContrastTests`, `NoctisAppContrastTests`, `NoctisPaperContrastTests`, `WelcomeContrastTests`). `QA_LEDGER.md` has 193 rows, 27 open or unverified [R]; the 18 minor layout rows UX-01 lists are "fixed in source, never re-photographed" [R].

### 4.2 Issues

Each issue below uses these fields: ID, audit ID, severity, classification, evidence, user impact, solution, files, tests, safe without owner decision.

**S1B-A01 · Button Shapes**
- Audit ID: UX-02, UX-03. Severity: Minor to Medium (a person who turned the setting on cannot see which text is tappable).
- Classification: **genuine defect** in code for custom plain styles; platform buttons already comply [A].
- Evidence: 77 `.plain` buttons and `NoctisTextButton` never read the setting [V]. SwiftUI adds button shapes to system styles, not to custom or `.plain` labels [A].
- Impact: text-only links and actions look like labels when Button Shapes is on.
- Solution: one view modifier (`noctisButtonShape()`) that reads `accessibilityShowButtonShapes` and adds a thin capsule outline or underline using existing design tokens. Apply it inside `NoctisTextButton` first (one place covers every text button built from it). For other `.plain` buttons, run a read-only inventory to split them into (a) text-only controls that need the modifier and (b) rows, cards and tiles that already have a visible container and need nothing. No change when the setting is off, so no redesign.
- Files: the file that defines `NoctisTextButton` (location to be confirmed in implementation; likely in the design-system package), plus only the call sites the inventory flags.
- Tests: unit test that the modifier adds a shape only when the setting is on (environment injection); EnvironmentProbe-based UI test on one screen with the setting on; simulator screenshot pass in 1B-5.
- Safe without owner decision: **yes** (setting-conditional only).

**S1B-A02 · Differentiate Without Color**
- Audit ID: UX-03. Severity: Major as written in the audit; I rate it **Medium** (impact not verified; most states already have words next to the colour).
- Classification: **needs inventory first**, then likely a genuine defect for any colour-only signal.
- Evidence: no shipped code reads the setting [V]. The app uses colour-coded states: Recovery bands, insight tones, rings and charts [R, source not exhaustively walked in this phase [N]].
- Impact: a colour-blind person, or one using this setting, could miss a state that only colour conveys.
- Solution: step 1, a read-only table of every colour-coded indicator and whether a text label, glyph or pattern already carries the same meaning. Step 2, for each colour-only case add a twin (an SF Symbol or a text token) that shows only when `accessibilityDifferentiateWithoutColor` is true. Charts get a pattern or marker shape, not a new colour. No look change when the setting is off.
- Files: the Recovery band view, insight tone chips, ring and chart views (named by the inventory), and a shared helper for "colour twin".
- Tests: unit tests on the band and tone models that every state has a non-colour descriptor (a table-driven test over all cases); UI test under the probe with the setting on.
- Safe without owner decision: **yes**, provided additions are setting-conditional. If the owner wants the twins always visible, that changes the look and becomes a decision (section 13).

**S1B-A03 · Smart Invert**
- Audit ID: UX-02. Severity: Minor.
- Classification: **genuine defect** for bitmap content; unknown for the rest [N].
- Evidence: `accessibilityIgnoresInvertColors` appears 0 times [V]. The share card is rendered to an image [R].
- Impact: under Smart Invert, images and the share-card preview invert and look wrong or unreadable.
- Solution: add `.accessibilityIgnoresInvertColors()` to share-card previews and any image or artwork views; leave the dark SwiftUI chrome alone (it follows the system). Simulator check of each image surface.
- Files: the share-card preview view, review/story views that show a rendered image, any artwork view (named by a grep for `Image(` and `UIImage` use during implementation).
- Tests: a source-scan test that every view displaying a `UIImage` or a rendered share card carries the modifier is feasible but brittle; prefer a short checklist test plus simulator screenshots.
- Safe without owner decision: **yes**.

**S1B-A04 · Reduce Transparency**
- Audit ID: UX-03. Severity: Low.
- Classification: **already handled by the platform** for system materials; **needs visual verification** for custom translucent fills and scrims.
- Evidence: one `glassEffect` [V], which adapts to the setting [A]. Custom `opacity`-based overlays and scrims (and Stage 1A's PrivacyShield cover) do not adapt; the cover is opaque by design [R].
- Solution: do not add code speculatively. In 1B-5, view each translucent surface with the setting on; add an opaque fallback only where text sits on a translucent fill and contrast drops.
- Files: none until the pass finds something.
- Tests: contrast tests already exist for the palette; extend only if a fallback is added.
- Safe without owner decision: yes.

**S1B-A05 · Bold Text**
- Audit ID: UX-03. Severity: Low.
- Classification: **already handled by the platform** for system fonts; **needs visual verification** for clipping and truncation.
- Evidence: the app relies on system text styles [R, not re-audited for custom-font use [N]]. `legibilityWeight` is read only by the probe [V].
- Solution: no code. Verify in 1B-5 that no screen clips or truncates with Bold Text on, especially fixed-height rows, the Watch pages and widgets. Any custom font found by a `Font.custom` grep needs a weight fallback.
- Safe without owner decision: yes.

**S1B-A06 · Increase Contrast**
- Audit ID: UX-02. Severity: Low to Medium.
- Classification: **partly handled** (8 reads of `colorSchemeContrast`) [V]; **needs visual verification**.
- Evidence: palette contrast ratios are tested for the default contrast only as far as I read [N whether the increased-contrast variants are asserted].
- Solution: confirm what the existing contrast tests assert; if increased contrast is not asserted, add the high-contrast ratios to the same tests. Then the visual pass.
- Safe without owner decision: yes.

**S1B-A07 · Reduce Motion**
- Audit ID: UX-02. Severity: Low.
- Classification: **already fixed in source** (108 reads) [V]; behaviour of the long-running animations (Breathing, Meditation, sleep sounds, Watch breathing) **needs a spot check**.
- Solution: no code. Spot check in 1B-5.
- Safe without owner decision: yes.

**S1B-A08 · On/Off Labels**
- Audit ID: UX-02. Severity: Low.
- Classification: **needs visual verification**. Native `Toggle` shows the I/O mark automatically [A]; custom switch-like controls (if any) would not.
- Solution: grep for custom toggle components during the inventory; if any exist, add the labelling; otherwise no code.
- Safe without owner decision: yes.

**S1B-A09 · Dynamic Type and the open layout rows**
- Audit ID: UX-01, X-27. Severity: Minor to Medium.
- Classification: **already fixed in source (reported), needs visual verification** [R].
- Evidence: 18 rows named in UX-01 (QA-081 to 098, 115, 116 and others) and about 26 open minor rows in X-27, all "fixed in source, not re-photographed" [R]. One RTL item (chevrons) is not a v1 concern because RTL languages are not shipped [R].
- Solution: re-run the existing screenshot suite at AX3 and AX5 on the final build, view the images, and close or reopen each row in the ledger with the evidence file. No code unless a row reproduces.
- Tests: reuse the existing UI/QA screenshot tests and contact-sheet script [R]. Do not claim a row closed until the image is viewed.
- Safe without owner decision: yes.

**S1B-A10 · VoiceOver traversal and accessibility focus**
- Audit ID: UX-02, X-27. Severity: Medium.
- Classification: **needs verification**: the traversal test is written but never run on the final build [R]. Stage 1A added a privacy cover whose VoiceOver behaviour (it should hide what is behind it) was a device item [R].
- Solution: run the traversal test, then a manual VoiceOver pass on: onboarding, Home, Sleep, Recovery, Coach (focus moves to the reply), Settings, modals and sheets (focus lands on the sheet, returns on dismiss), the wind-down and alarm screens, the paywall, and the privacy cover (nothing behind it is focusable). Fix only what reproduces.
- Safe without owner decision: yes.

**S1B-A11 · Touch targets (44 pt)**
- Audit ID: X-27. Severity: Low.
- Classification: **needs verification** [N]; I did not measure targets this phase.
- Solution: add the 44 pt check to the same Accessibility Inspector pass; fix by `contentShape` and minimum frames only where a target is under size.
- Safe without owner decision: yes.

**S1B-A12 · Charts and status indicators for assistive technology**
- Audit ID: UX-03. Severity: Medium.
- Classification: **needs verification** [N].
- Evidence: not examined in this phase beyond noting that charts and rings are colour-coded.
- Solution: during the inventory (A02) also record, for each chart and ring, its accessibility label, value and (for Swift Charts) whether an audio-graph description exists. Add label and value text where missing. This is the VoiceOver counterpart of A02.
- Tests: table-driven test that each chart model produces a non-empty description string.
- Safe without owner decision: yes.

### 4.3 Order and effort for Track A

Inventory first (read-only, produces the lists for A01, A02, A03, A08, A12), then code (A01, A02, A03), then the verification pass (A04 to A07, A09 to A11). Track A is mostly visual verification; the code part is a handful of modifiers and a few twins.

---

## 5. Database and reliability findings (Track B)

### 5.1 What exists [V]

- SwiftData stores use `VersionedSchema` with a `SchemaMigrationPlan` that has no stages, `cloudKitDatabase: .none`, and `StoreRecovery` that quarantines a damaged store after a SQLite `quick_check` (`SQLiteCheck`) instead of deleting it.
- JSON stores (Journal, Coach history, alarm, preferences) carry a version and are version-guarded on read.
- Delete-all runs through `DataManager`'s `DeletionRunner` with steps wired in `AppRoot/DataWiring.swift`; it removes store files, JSON files, caches, notifications and preferences, and it bumps the Watch data epoch and sends the Watch a wipe context.
- Backup exclusion and file-protection settings are applied to the data directories and, since Stage 1A, to export files.
- No `VACUUM`, `wal_checkpoint` or compaction exists anywhere [V]. The Keychain item for the Apple sign-in identity is never reset on a fresh install [V].
- Tests: `StoreSafetyTests.swift` holds `SchemaVersionTests`, `SchemaMigrationTests` (a synthetic V2 proves the harness) and `StoreDamageTests`.

### 5.2 Issues

**S1B-B01 · Migration readiness**
- Audit ID: X-16. Severity: Medium (future risk, not a current defect).
- Classification: **partly addressed**: the harness exists and is tested with synthetic versions [V]; there is no real second version to test, and none should be created.
- Impact: when v1.1 changes a `@Model`, a missing version bump or a wrong stage would damage or lose data on update; today nothing forces the developer to notice.
- Solution (smallest safe): (a) a schema fingerprint test: record the current entity names, attribute names and types in the test; the test fails with a clear message ("a @Model changed: add a VersionedSchema stage and update this fingerprint"). (b) a short `Docs/MIGRATION_PROCEDURE.md` written for the developer: when to add a version, how to build the old-store fixture from a v1.0 simulator store, the pre-release upgrade test (install v1.0 build, add data, update, check). (c) record that real upgrade testing is a release-time device task [D]. No artificial V2.
- Files: new `SchemaFingerprintTests.swift`, new `Docs/MIGRATION_PROCEDURE.md`, an entry in `Docs/POST_LAUNCH.md`.
- Tests: the fingerprint test itself; existing migration tests unchanged.
- Safe without owner decision: **yes**.

**S1B-B02 · Interrupted delete-all**
- Audit ID: section 16, X-15 (related). Severity: Medium for privacy trust, Low in likelihood.
- Classification: **genuine gap** [V]: the runner keeps no persisted progress, so a kill, crash or reboot midway leaves a part-deleted state and the next launch continues as if nothing happened.
- Risk scenarios: stores deleted but alarm notifications still scheduled; JSON gone but SwiftData present; the Watch told to wipe before the iPhone finished (acceptable) or never told (not acceptable); widgets or Watch showing old data after the iPhone side finished.
- Solution: write a `pendingDeleteAll` marker (a small value in UserDefaults) **before** the first destructive step. On launch, before any store opens, if the marker is present, run the same runner again; every step is already idempotent as written (deleting what is not there is a no-op) [V for the steps I read; confirm each step during implementation]. The marker is cleared as the very last step, after preferences. Bump the Watch epoch and send the wipe context at the start so the Watch drops its copy even if the iPhone is killed later. The re-run must also cancel pending alarm notifications and republish an empty snapshot so widgets clear.
- Files: `NoctisCore/DataManager.swift`, `AppRoot/DataWiring.swift`, `AppRoot/AppContainer.swift` (launch hook), `NoctisCore/WatchSync/WatchSyncService.swift` (epoch ordering check only).
- Tests: runner tests that kill after each step index (simulate by throwing) and assert the next launch completes the deletion; assert the marker clears only at the end; assert the epoch is bumped before the first removal. A real kill mid-delete is a device check [D].
- Safe without owner decision: **yes**.

**S1B-B03 · SQLite deletion remnants**
- Audit ID: X-15 (the free-pages half; the app-switcher half was Stage 1A). Severity: Low.
- Classification: **confirmed [V]**: deleted rows can remain in free pages of a store that was not deleted (per-category deletion, such as deleting journal entries or Coach history held in SwiftData, leaves the file in place).
- Important framing: deleting every store file (delete-all) already removes those pages. The remnant exists only after a partial delete. iOS Data Protection already encrypts the file at rest [A]. I recommend **no forensic claim** anywhere: the documentation may say space is reclaimed, not that data cannot be recovered.
- Solution (smallest safe): after a per-category delete that touches a SwiftData store, set a "compact on next launch" flag. On the next launch, before the container opens, if `quick_check` passes and free disk space is at least twice the store size, run `PRAGMA wal_checkpoint(TRUNCATE)` then `VACUUM` once on a direct connection, then clear the flag. `VACUUM` is transactional, so a crash during it does not corrupt the store [A]; on failure, leave the store alone and clear nothing so it retries. No background loops, no repeated runs. The cost is proportional to store size, which for this app is small [N: store sizes not measured].
- Files: new small helper beside `StoreRecovery.swift` (`StoreCompaction`), `DataManager.swift` (set the flag), `AppContainer.swift` (run before the container opens).
- Tests: create a store, insert and delete rows, compact, assert file size dropped and row count correct; assert nothing runs when the integrity check fails or when free space is short; assert the flag clears only on success.
- Safe without owner decision: yes to implement; the owner may prefer to defer it (low value, small risk). Listed as an owner choice in section 13.

**S1B-B04 · Keychain lifecycle after reinstall**
- Audit ID: X-11, SEC-01. Severity: Minor.
- Classification: **confirmed [V]** (`AccountStore.swift` keeps the identity in the Keychain, which can outlive an uninstall [A]; no first-run reset exists).
- Impact: a reinstalled app can start "signed in" with an empty profile until it checks the credential with Apple, which is confusing and shows a name the person may expect to be gone.
- Solution: a first-launch marker in UserDefaults (which is deleted on uninstall). Before `AccountStore` reads anything: if the marker is absent **and** no NOCTIS store file exists, delete the Keychain item, then set the marker. The second condition protects people who restore a backup or update an existing install where the marker is missing for any reason: they keep their sign-in. This preserves Sign in with Apple in every normal launch and after updates, and a person who reinstalls simply taps Sign in with Apple again.
- Timing: this must ship in the first release. Added after release, an update would run with the marker absent on every existing install; the store-file condition is what keeps it safe, so it must be tested.
- Edge to confirm: whether the Keychain item uses a `ThisDeviceOnly` accessibility class, because that decides what a device-to-device restore does [N].
- Files: `NoctisCore/Account/AccountStore.swift`, `AppRoot/AppContainer.swift` (call order), `Docs/PRIVACY_REPORT.md`.
- Tests: `AccountStoreTests` additions: marker absent plus no store clears the item; marker absent plus store present keeps it; marker present keeps it; the marker is not removed by delete-all (or, if it is, delete-all also handles the Keychain, to be decided in implementation and tested either way).
- Safe without owner decision: **yes**.

**S1B-B05 · Backup, restore and accurate privacy documentation**
- Audit ID: section 16, X-15. Severity: Low.
- Classification: **needs a wording audit** [N exact current wording against the exclusion list].
- Solution: list, from the code, exactly which directories are excluded from device backup and which are not, and which files carry which protection class. Then make `Docs/PRIVACY_REPORT.md`, `Docs/site/privacy.html` and the store listing say exactly that, no more. Add a plain statement about moving to a new phone: NOCTIS keeps its data on the device; whether it comes back depends on the backup rules above; there is no cloud copy. Do not claim anything about forensic recovery.
- Files: three documents plus a test, if one exists, that compares the document claims to the inventory (`DataInventory` tests).
- Tests: extend the data-inventory test so the backup and protection statements are generated from, or checked against, the same list.
- Safe without owner decision: the wording about a new phone is an owner approval item (section 13).

**S1B-B06 · Coverage check across stores**
- Audit ID: section 16. Severity: Low.
- Classification: verification task. Confirm every store and file the app writes (SwiftData stores, Journal, Coach history, alarm, preferences, snapshot, Watch files, caches, exports) appears in `DataInventory` and in both delete paths. The inventory test already exists [R]; the plan adds only a check that a new file written without an inventory entry fails a source-scan test.
- Safe without owner decision: yes.

### 5.3 Options considered and rejected

- A real V2 schema to "test migrations": rejected; it creates a permanent migration that must be maintained.
- Deleting the store and rebuilding from HealthKit on any integrity failure: rejected; Journal and Coach history do not come back, and `StoreRecovery` already quarantines instead.
- A full `VACUUM` on every launch: rejected; expensive and unnecessary.
- Secure-delete claims: rejected; cannot be proven.

---

## 6. Subscription findings (Track C)

### 6.1 How entitlement flows today [V]

StoreKit 2 transactions go to `EntitlementClient`, which feeds `EntitlementManager` and `EntitlementResolver.resolve` (`PremiumKit/Entitlement.swift`). The resolver counts verified transactions only, ignores revoked ones, honours the grace-period end date, and treats family-shared ownership as Premium. The result becomes the app's `Tier`. Three copies of that answer exist:

1. `EntitlementCache`: one word in UserDefaults, used as a launch hint until StoreKit answers (app only).
2. `WidgetSnapshot.tier` (key `t`): written to the App Group file and read by widgets, complications and Siri/Shortcuts through `IntentRuntime.tier()` (`WidgetGate.swift:59`, `WidgetSpoken.swift:44`, `IntentRuntime.swift:80`).
3. The copy inside the snapshot sent to the Watch (`WatchContext`), then stored Watch-side and read by Watch pages (`WatchPages.swift:282,315`) and complications.

`WidgetPublisher` republishes when the tier changes, and skips a write when the content is the same. Extensions and the Watch never call StoreKit (R62 [R]; consistent with the code I read). `BackgroundRefresher`'s refresh closure runs only `homeRepository.refresh` (`AppContainer.swift` around 393 to 445); nothing refreshes entitlement on a background wake [V].

### 6.2 Issues

**S1B-C01 · Expiry-aware tier for widgets, complications, Siri and Watch**
- Audit ID: P-03, X-09 (and FUNC-04). Severity: Major but not blocking (revenue and trust leak, not a store violation).
- Classification: **confirmed [V, and documented in `POST_LAUNCH.md` as a known gap]**.
- Evidence: the snapshot holds a tier with no end date. If the plan ends while the app is not running, no code path changes the tier until the app next runs and republishes. `WidgetTimelineBuilder` builds entries across a 12-hour horizon from the snapshot as it was written, so it cannot know the plan is about to end.
- Impact: a lapsed person keeps Premium widgets, complications and Siri answers for as long as they do not open the app.
- Solution, in five pieces:
  1. **Snapshot metadata.** Add `premiumUntil` (seconds since epoch, optional) and `autoRenews` (Bool) to `WidgetSnapshot` (the next compact keys after `t`), populated by `WidgetSnapshotMaker` from the entitlement result. Source of the date: the entitling transaction's expiration; during a grace period, the grace-period expiration; for a family-shared plan, the same transaction expiration. A lifetime or non-expiring entitlement (none exists today) would leave it nil.
  2. **One seam.** `WidgetSnapshot.effectiveTier(at now: Date) -> Tier`: Premium stays Premium unless `premiumUntil` exists and `now >= premiumUntil + slack`, where `slack` is zero when `autoRenews` is false and a configured interval when it is true. Every reader (`WidgetGate`, `WidgetSpoken`, `IntentRuntime.tier()`, Watch gating, complication views) calls this and never reads `tier` directly. A source-scan test enforces that (see S1B-X01).
  3. **Why slack.** If the plan auto-renews, the renewal usually happens near the end date but the snapshot is not rewritten until the app runs. Locking exactly at the end date would lock a paying person whose renewal went through. Apple states that renewal can occur before the end date and that billing problems trigger retry or grace states rather than an immediate stop [A]. Wrongly locking a payer is worse than letting a lapsed person keep widgets for a short, bounded time. Proposed default: 48 hours when `autoRenews` is true, zero when false. The value is an owner choice (section 13); the code takes it as a single constant.
  4. **Timeline entry at lock time.** `WidgetTimelineBuilder` adds an entry at `premiumUntil + slack` when it falls inside the horizon, built from `effectiveTier(at: entry.date)`, so the widget re-renders on its own without the app. The timeline's reload policy already re-asks at the horizon end, which covers dates beyond it. Watch complications, which are WidgetKit timelines too, must use the same builder or the same function (confirm in implementation which builder `Watch/Widgets/NOCTISWatchWidgets.swift` and `NoctisWatchKit/WatchComplications.swift` use [N]).
  5. **Republish timing.** The metadata changes on renewal (new end date), on cancellation (`autoRenews` flips), on grace entry and on purchase, so `WidgetPublisher`'s same-content check sends a new write each time and the Watch gets a new context. This also makes the Watch correct when it is offline from the phone, because the Watch computes the same function locally.
- Size: the snapshot is capped at 3,072 bytes in both `WidgetSnapshotStore` and `WatchInbox`, and the Watch wire at 4,096 [V]. Two more keys add a few dozen bytes; the plan requires measuring a worst-case snapshot first, and a test asserting headroom (S1B-X02), because an over-size snapshot is rejected silently on write.
- Files: `NoctisWidgetKit/WidgetSnapshot.swift`, `WidgetTimeline.swift`, `WidgetGate.swift`, `WidgetSpoken.swift`, `NoctisCore/WidgetSnapshotMaker.swift`, `WidgetPublisher.swift`, `NoctisCore/Store/EntitlementManager.swift` (expose the end date and renewal flag), `NoctisIntentKit/IntentRuntime.swift`, `NoctisWatchKit/WatchPages.swift`, `WatchComplications.swift`, `WatchInbox.swift`.
- Tests: snapshot round trip and version/compat (extend `WidgetSnapshotTests`, `TierSnapshotTests`); `effectiveTier` table test (before, at, after the date; slack on and off; grace; nil date); timeline test that a lock entry exists and flips (extend `WidgetTimelineTests`); gating tests with a clock that moves past the date (extend `WidgetGatingTests`, `IntentGatingTests`, `WatchGatingTests`); a StoreKitTest that the snapshot carries the right end date after purchase, renewal, cancellation and grace; source scan for direct `tier` reads.
- Real-world check: a real expiry on a device with a Sandbox or TestFlight account while the app stays closed [D]. StoreKitTest can speed time but cannot reproduce the widget process or the system's timeline scheduling (section 11).
- Safe without owner decision: **yes with the proposed defaults**; the slack length should be confirmed before release.

**S1B-C02 · Refresh entitlement on background wake**
- Audit ID: P-03. Severity: Medium.
- Classification: **genuine gap** [V]: `Transaction.updates` is only observed while the app runs, and `BackgroundRefresher` does not refresh entitlement.
- Solution: in the same background paths that already refresh Health data (background app refresh and any HealthKit background delivery wake), also call the existing `EntitlementManager.refresh()` and let `WidgetPublisher` republish. Keep it bounded by the wake's time limit and never block the Health refresh on it. No StoreKit in widget or Watch extensions.
- Files: `AppRoot/AppContainer.swift` (the refresher closure), `NoctisCore/Store/EntitlementManager.swift` only if it needs a non-UI entry point.
- Tests: refresher test that a background run calls the entitlement refresh once and that a failure does not fail the Health refresh; offline: the cached tier still publishes with the current end date.
- Safe without owner decision: yes.

**S1B-C03 · Billing-problem presentation**
- Audit ID: P-04. Severity: Medium.
- Classification: **partly done**: billing retry with a grace period is reported as grace and billing retry without grace ends Premium in the rules, both covered by StoreKitTests (`billingRetryWithAGracePeriodIsReportedAsGraceByTheStore`, `billingRetryWithNoGracePeriodIsReportedAsRetryAndEndsPremiumInTheRules`) [V]. `SubscriptionSummary.swift` has grace copy (about line 70) but **no copy for billing retry without a grace period** [V].
- Impact: a person whose payment failed and who has no grace period loses Premium with no explanation and no hint to fix the payment method.
- Solution: add the two states to `SubscriptionSummary` and the Subscription settings page: "In grace period: your payment did not go through, update your payment method; access continues until <date>" (exists) and "Payment problem: Premium is paused until Apple can charge your payment method; update it in Settings > Apple Account > Subscriptions" (new). Link to the system subscription management sheet already used by the app. No pricing words, no alarming language. The widget and Watch need no new text: they show the locked state.
- Files: `NoctisCore/SubscriptionSummary.swift`, the Settings subscription page view, `Docs/store/` copy if it describes these states.
- Tests: summary tests for each state (extend whatever tests cover `SubscriptionSummary`); the existing StoreKitTests keep covering the state detection.
- Safe without owner decision: copy wording is an owner approval item (section 13); the logic is safe.

**S1B-C04 · Product metadata: fetching, refresh, cache, offline**
- Audit ID: P-04. Severity: Low to Medium.
- Classification: **confirmed [V]**: `renewal()` calls `Product.products` on every refresh, and on failure returns nil, so an offline refresh cannot learn the billing state (the tier itself still resolves from local entitlements, which StoreKit serves from its local record [A]).
- Solution: (1) read subscription status through the subscription group status API (`Product.SubscriptionInfo.status(for:)`), which does not need a fresh product fetch per refresh; verify the exact API shape against current Apple docs first [A]. (2) Fetch products for the paywall when the paywall opens and on explicit retry, not on every entitlement refresh. (3) Keep the existing behaviour that a failed reload keeps already-loaded plans (covered by `aReloadThatFailsKeepsThePlansAlreadyLoaded`) and that an unreachable store shows "unavailable" rather than empty or free (`aStoreThatCannotLoadProductsLeavesThePaywallUnavailableNotEmptyOrFree`) [V]. (4) Do not cache prices across launches: a stale price from the wrong storefront is worse than "unavailable, retry". (5) Cache only the last known billing state with a timestamp so the Subscription page can say "last checked <date>" when offline.
- Files: `NoctisCore/Store/StoreManager.swift`, `EntitlementManager.swift`, `EntitlementClient.swift`, `EntitlementCache.swift`, `SubscriptionSummary.swift`.
- Tests: StoreKitTest cases for status without a product fetch; offline simulated by a client that throws on the product call; existing store tests must keep passing.
- Safe without owner decision: yes.

**S1B-C05 · Family Sharing**
- Audit ID: P-05, REL-03. Severity: Minor, decision item.
- Reported separately, as the brief requires:
  - **Code support [V]:** `EntitlementResolver` treats family-shared ownership as Premium. There is a StoreKit test that the configuration has Family Sharing off (`familySharingIsOffInTheConfigurationSoThereIsNothingToBuy`).
  - **StoreKit configuration [V]:** `Config/Noctis.storekit` has `familyShareable: false`.
  - **App Store Connect:** not visible from this repository [N]. Enabling Family Sharing for a subscription cannot be turned off afterwards [A, verify in the current App Store Connect help before the owner decides].
  - **Behaviour with it on:** untested on a real account [R] [D].
- This plan does **not** enable Family Sharing. Recommendation: leave it off for 1.0 and revisit after launch, because the decision is permanent and the behaviour is unverified on real accounts. Owner decision (section 13).

**S1B-C06 · What StoreKitTest can and cannot prove (P-07)**
- Audit ID: P-07. Severity: Info.
- StoreKitTest runs in the test process against `Noctis.storekit` [V]. It cannot reproduce the real App Store's timing of renewals, real billing retry and grace lengths, a real declined Ask to Buy through the system sheet, widget-process timeline behaviour, or Apple's server notifications [R, QA-129]. The plan therefore splits verification into two columns in section 6.3 and section 11 and never reports a Sandbox-only scenario as verified from StoreKitTest.

### 6.3 The 19 scenarios

"Code" shows where the behaviour lives; "StoreKitTest" says whether an automated test already exists [V from test names in `Tests/StoreTests/StoreKitSessionTests.swift`], needs adding, or cannot reproduce it; "Real" says whether Sandbox, TestFlight or a device is still needed.

| # | Scenario | Code path | StoreKitTest | Real Sandbox, TestFlight or device |
| --- | --- | --- | --- | --- |
| 1 | First purchase | StoreManager, EntitlementManager | exists (yearly and monthly buy tests) | Sandbox purchase sheet [D] |
| 2 | Monthly plan | same | exists (`buyingMonthlyIsPremiumWithoutATrial`) | Sandbox [D] |
| 3 | Annual plan | same | exists (`buyingYearlyStartsTheTrialAndUnlocksEverySurface`) | Sandbox [D] |
| 4 | Free trial | same, intro offer | exists | Sandbox trial eligibility rules [D] |
| 5 | Trial expiry or conversion | resolver, renewal | exists (`theTrialConvertsToAPaidYearAndStaysPremium`) | real timing [D] |
| 6 | Renewal | resolver, Transaction.updates | exists (`aRenewalMovesTheEndDateForward...`, in-session renewal) | renewal while the app is closed [D] |
| 7 | Cancellation (still active until end) | summary, resolver | exists (`cancellingAutoRenewKeepsPremiumUntilTheEnd...`) | none beyond Sandbox |
| 8 | Expired | resolver, locks | exists (`anExpiredPlanIsFree...`, `premiumEndsOnItsOwn...` in session) | **expiry while terminated: P-03, needs new tests and a real expiry [D]** |
| 9 | Refund | resolver (revoked ignored) | exists (`aRefundTakesPremiumAway`) | Sandbox refund is not reliable; treat as simulated |
| 10 | Revoked | resolver | covered by the refund test; add a direct revoked case | not reproducible |
| 11 | Restore | AppStore.sync, StoreManager | exists (`restoreFindsAPurchaseOnAFreshInstall`) | Sandbox account on a second install [D] |
| 12 | Other device | Transaction.updates | exists in spirit (`aPurchaseMadeWhileTheAppWasNotRunningArrivesThroughTransactionUpdates`) | two real devices [D] |
| 13 | Family Sharing | resolver ownership branch | config-off test exists; the shared-ownership branch needs a resolver unit test | real family account [D], and only if enabled |
| 14 | Pending (Ask to Buy) | StoreManager | exists (approved and declined tests) | the real system sheet [D] |
| 15 | Billing problem (grace and retry) | resolver, summary | exists (both billing-retry tests) | real timing and lengths [D]; new summary copy needs tests (C03) |
| 16 | Offline launch | EntitlementCache, StoreKit local record | exists (`aLaunchWithTheLastTierCachedIsRightBeforeTheStoreAnswersAndWithNoNetwork`) | airplane-mode device launch [D] |
| 17 | Expiry while the app is terminated | snapshot, timeline, background refresh | **missing: add (C01, C02)** | **real expiry [D]** |
| 18 | Widgets and complications state | snapshot, timeline builder, Watch inbox | partial (gating tests with injected tiers); **missing: expiry-aware tests** | real widget and Watch device pass [D] |
| 19 | Siri and Shortcuts | `IntentRuntime.tier()`, intent gating | exists (`IntentGatingTests`, tier injection); **missing: expiry-aware case** | on-device Shortcut run [D] |

Most of the subscription logic is already covered by StoreKitTest. The new work is concentrated in scenarios 17, 18 and 19, plus the summary copy for 15.

---

## 7. Apple Watch findings (Track D)

### 7.1 What exists [V]

- Entry: `Watch/App/NOCTISWatchApp.swift` and `WatchRootView.swift`; five pages built by `NoctisWatchKit/WatchPages.swift` and drawn by `WatchViews.swift` (the five-page experience stays as is).
- Receiver: `WatchSnapshotReceiver.swift` takes `didReceiveApplicationContext` and `didReceiveUserInfo` (the complication transfer carries the same dictionary), handles `.backgroundTask(.watchConnectivity)` through `finishPendingContent`, and can ask the iPhone for an update only while the phone is reachable (`sendMessage`, no content in either direction).
- Ordering: `WatchInbox` accepts a context only if its data epoch is higher, or equal with a newer generated-at; a higher epoch with no snapshot wipes the Watch copy.
- iPhone side: `WatchSyncService` sends the latest context with `updateApplicationContext` (latest value replaces the pending one [A]); after delete-all it bumps the epoch to "now" but never below the previous epoch plus one and sends a wipe context; it never sends a snapshot older than its own epoch.
- Complications: sent through `transferCurrentComplicationUserInfo` only when the day changed or recovery first appeared for the day, only if the complication is enabled and only within the system's remaining budget (about 50 per day [A]). The Watch reloads complication timelines after applying a context (`WatchModel.swift:55`).
- Privacy: Health numbers on Watch pages and complications are `privacySensitive` (`WatchViews.swift`, `WatchComplicationViews.swift`), which redacts them on a locked or dimmed display [A]. The Watch app has no scene-phase privacy handling except in the breathing session (`WatchBreathing.swift:184`).

### 7.2 Issues

**S1B-D01 · Subscription expiry on the Watch**
- Audit ID: P-03, X-09. Severity: Major but not blocking, same root as C01.
- Solution: the Watch computes `effectiveTier(at:)` locally from the received snapshot, so it locks at the right moment even with the phone away. No new Watch-side StoreKit.
- Files: `NoctisWatchKit/WatchPages.swift`, `WatchComplications.swift`, `WatchInbox.swift`, Watch widgets file.
- Tests: extend `WatchGatingTests`, `WatchComplicationTests` with a moving clock.
- Safe without owner decision: yes (same slack decision as C01).

**S1B-D02 · Complication wake ignores tier changes**
- Audit ID: X-09 (related). Severity: Medium.
- Classification: **genuine gap [V]**: `wakeComplicationIfNeeded` records "day:hasRecovery" only. A purchase, cancellation flip or renewal that changes `premiumUntil` does not use the complication transfer, so the complication relies on the Watch app getting background time to apply the application context.
- Solution: add the tier and `premiumUntil` to the wake condition (a new component in the complication mark), still guarded by the enabled flag and the remaining budget, and still skipped when the budget is zero. This keeps the budget impact to a few extra transfers per month, not per day.
- Files: `NoctisCore/WatchSync/WatchSyncService.swift`, `WatchSyncDefaults.swift` (the mark format), `NoctisWatchKit/WatchComplications.swift`.
- Tests: extend `WatchSyncTests` with a mock session: tier change triggers one transfer; same tier does not; zero budget does not transfer and does not mark.
- Safe without owner decision: yes.

**S1B-D03 · App-switcher and Dock snapshot privacy on the Watch**
- Audit ID: X-15 (the app-switcher half, Watch side). Severity: Low to Medium, **unknown until tested**.
- Classification: **needs device verification [D]**; documentation I could reach did not settle whether watchOS snapshots the app UI for the Dock or recents and whether `privacySensitive` applies there [A].
- Constraint: do not copy the iOS PrivacyShield. A full cover on the Watch would hurt glanceability and the always-on display, and iOS's cover relies on APIs and behaviours that differ.
- Solution: first, a device pass: open each page with Health numbers, lower the wrist, open the Dock and recents, and look at what the snapshot shows with the watch locked and unlocked. If numbers are exposed, apply the smallest change: on `scenePhase != .active`, redact only Health values with the system's privacy redaction on the Watch pages, leaving the layout intact. No private APIs. If not exposed, record the evidence and change nothing.
- Files: `Watch/App/WatchRootView.swift`, `WatchViews.swift` only if the device pass requires it.
- Tests: unit test that the sensitivity mapping marks every Health value (exists in spirit in `WatchPagesTests`); device evidence for the rest.
- Safe without owner decision: yes; the implementation itself is conditional on the device result.

**S1B-D04 · Stale or missing data on the Watch**
- Audit ID: X-09 (related). Severity: Low.
- Classification: **partly verified**: ordering rules cover old and duplicate transfers [V]; the wording the Watch shows when the data is old or the phone is unreachable lives in `NoctisWatchKit` state files I did not read in full [N].
- Solution: read the stale-state text and check three cases on a device: phone off for a day (stale day), phone back (fresh), and deletion on phone while the Watch is away. Fix wording only if it claims freshness it does not have.
- Safe without owner decision: yes.

**S1B-D05 · Deletion propagation**
- Audit ID: section 16. Severity: Medium if broken; **currently looks sound**.
- Classification: **already fixed in source [V]** by the epoch design: delete-all sets a higher epoch and sends a wipe context; because `updateApplicationContext` keeps only the latest value, a later snapshot replaces the wipe context, but it carries the higher epoch and therefore also clears the Watch's older data before being accepted.
- Remaining work: add tests for the sequence delete-all while disconnected, then a new snapshot, then reconnect (Watch must end with only the new data and never show old data), and for a kill during delete-all (B02). Confirm on devices [D].
- Files: tests only, unless the sequence test fails.
- Safe without owner decision: yes.

**S1B-D06 · Complication refresh limits**
- Audit ID: X-09 (related). Severity: Low.
- Classification: **by design** [A]: complication data transfers are budgeted and WidgetKit refreshes are budgeted per day. The plan adds no new periodic transfer. The expiry lock entry in C01 is a timeline entry, not a reload, so it costs no extra refresh budget.
- Solution: document the limits in `Docs/POST_LAUNCH.md` and keep the existing `signpost` of the remaining budget; no code beyond D02.
- Safe without owner decision: yes.

**S1B-D07 · Preserve the five-page experience**
- A constraint, not a defect: none of D01 to D06 adds, removes or reorders a page.

---

## 8. Cross-platform architecture findings

### 8.1 The path, as it is [V]

iPhone StoreKit and Health → `EntitlementManager` and repositories → `WidgetSnapshotMaker` → `WidgetPublisher` (skips unchanged writes) → App Group snapshot file → WidgetKit (timeline from `WidgetTimelineBuilder`, 12-hour horizon) and `IntentRuntime` (reads tier from the file) → `WatchSyncService` (`updateApplicationContext`, plus a budgeted complication transfer) → `WatchInbox` (epoch and generated-at ordering) → Watch app pages and Watch complications.

### 8.2 Findings

**S1B-X01 · Entitlement is represented three times, with no time dimension**
- Representations: `EntitlementCache` word (app only), `WidgetSnapshot.tier` (shared file), the Watch copy. Only the first is allowed to be stale by design (a launch hint); the other two can be stale in an unbounded way (P-03).
- Recommendation: StoreKit stays the source of truth; the snapshot is the **only** cross-process representation and carries enough metadata (`premiumUntil`, `autoRenews`) to be evaluated at any time; `EntitlementCache` stays app-only. No new architecture, only one function (`effectiveTier(at:)`) and a rule that nothing else decides tier. Enforce with a source-scan test that fails on a direct read of the snapshot's `tier` outside that function and its serializer. Safe without owner decision.

**S1B-X02 · Snapshot size headroom**
- The 3,072-byte cap is enforced in two places and an over-size write fails silently [V]. Adding two keys is probably fine; this must be measured (largest snapshot: many factors, an alarm, recovery factors, full history count) and covered by a test that fails when the worst case exceeds, say, 90 percent of the cap. Safe: yes.

**S1B-X03 · Refresh triggers are incomplete**
- Today: app foreground, the Health refresh, tier change, and the background refresher's Health work. Missing: entitlement on background wake (C02), tier or end-date change in the complication wake (D02), and a timeline entry at the lock time (C01). With these three the data path has a trigger for every state change that matters. No other trigger is proposed.

**S1B-X04 · Races and ordering**
- Snapshot write versus Watch send: the snapshot is stamped with the current epoch before sending, so an older snapshot cannot overwrite newer data [V].
- Entitlement refresh versus Health refresh: two republish calls close together are safe because writes are idempotent and the Watch accepts equal epoch with newer generated-at [V]; confirm `generatedAt` advances on every republish, including a tier-only change, or the Watch may ignore a tier-only update as "not newer" [N, must be tested in C01]. This is a likely bug site and gets its own test.
- Invalid snapshot: oversize or undecodable data is dropped on both sides [V].

**S1B-X05 · Items still not verified in the cross-platform path**
- `NoctisIntentKit` authentication and unlock policies for individual intents; the stale-text logic in `NoctisWatchKit/WatchState`; whether the Watch widgets use the same timeline builder as the iPhone widgets. All three are listed in the implementation steps as "read before change".

---

## 9. Prioritized implementation roadmap

Priority is by user impact and risk. IDs refer to sections 4 to 8.

| Priority | Item | IDs | Why now |
| --- | --- | --- | --- |
| P1 | Expiry-aware tier, snapshot metadata, timeline lock entry, Watch follow-through | S1B-C01, D01, X01, X02, X04 | Largest real gap; revenue and trust; small and testable |
| P1 | Background entitlement refresh | S1B-C02, X03 | Without it the snapshot metadata goes stale when the app is closed for days |
| P1 | Keychain first-launch marker | S1B-B04 | Must ship in 1.0 or it needs the more careful "existing install" path |
| P2 | Billing-problem presentation, status read without a product fetch | S1B-C03, C04 | Honest messaging; fewer failures offline |
| P2 | Interrupted delete-all resume | S1B-B02, D05 | Privacy trust; small |
| P2 | Complication wake on tier change | S1B-D02 | Closes the Watch half of C01 |
| P2 | Button Shapes, Differentiate Without Color, Smart Invert, chart text | S1B-A01, A02, A03, A12 | Genuine accessibility defects; setting-conditional so low risk |
| P3 | Schema fingerprint test and migration procedure | S1B-B01 | Protects v1.1, no user impact today |
| P3 | Guarded compaction | S1B-B03 | Low value; owner may defer |
| P3 | Backup, restore and privacy wording audit | S1B-B05, B06 | Accuracy, cheap |
| Verify | AX layout re-shoot, VoiceOver, Tier C, contrast, Bold Text, Reduce Transparency, touch targets | S1B-A04 to A11 | Needs simulator and device; produces ledger evidence |
| Verify | Watch device pass, Sandbox and TestFlight pass | S1B-D03, D04, C06 | Real conditions only |
| Hold | Family Sharing | S1B-C05 | Owner decision |

Dependencies: C01 before D01, D02 and X02's test; C02 needs C01's metadata to be useful; the Differentiate Without Color inventory (A02) feeds A12; B02's test for epoch order depends on reading the current delete-all step order first.

---

## 10. Exact files expected to change

Paths relative to the repository root. "Confirm" means the file exists but I have not yet opened it for this purpose, or the exact location is not known yet.

Subscription and snapshot (1B-1):
- `Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetSnapshot.swift`
- `Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetTimeline.swift`
- `Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetGate.swift`
- `Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetSpoken.swift`
- `Packages/NoctisKit/Sources/NoctisCore/WidgetSnapshotMaker.swift`
- `Packages/NoctisKit/Sources/NoctisCore/WidgetPublisher.swift`
- `Packages/NoctisKit/Sources/NoctisCore/Store/EntitlementManager.swift`
- `Packages/NoctisKit/Sources/NoctisCore/Store/StoreManager.swift`
- `Packages/NoctisKit/Sources/NoctisCore/Store/EntitlementClient.swift`
- `Packages/NoctisKit/Sources/NoctisCore/Store/EntitlementCache.swift` (only if the cache gets a timestamp)
- `Packages/NoctisKit/Sources/NoctisCore/SubscriptionSummary.swift`
- `Packages/NoctisKit/Sources/NoctisIntentKit/IntentRuntime.swift`
- `Packages/NoctisKit/Sources/NoctisWatchKit/WatchPages.swift`, `WatchComplications.swift`, `WatchInbox.swift`
- `Packages/NoctisKit/Sources/NoctisCore/WatchSync/WatchSyncService.swift`, `WatchSyncDefaults.swift`
- `Packages/NoctisKit/Sources/AppRoot/AppContainer.swift`
- Settings subscription page view (confirm file under `ProfileFeature`)
- `Watch/Widgets/NOCTISWatchWidgets.swift` and `Widgets/Home/NoctisWidgets.swift` (confirm: only if they do not already go through the shared builder)

Data reliability (1B-2):
- `Packages/NoctisKit/Sources/NoctisCore/DataManager.swift`
- `Packages/NoctisKit/Sources/AppRoot/DataWiring.swift`
- `Packages/NoctisKit/Sources/NoctisCore/StoreRecovery.swift` or a new `StoreCompaction.swift` beside it
- `Packages/NoctisKit/Sources/NoctisCore/Account/AccountStore.swift`
- `Docs/MIGRATION_PROCEDURE.md` (new), `Docs/POST_LAUNCH.md`, `Docs/PRIVACY_REPORT.md`, `Docs/site/privacy.html`, `Docs/store/APP_STORE_LISTING.md`

Accessibility (1B-3):
- the design-system file defining `NoctisTextButton` (confirm), a new shared accessibility helper (button shape, colour twin) in the same module, call sites named by the inventory, share-card and image views (confirm), Recovery band, insight tone and chart views (confirm)
- `Docs/QA_LEDGER.md` and evidence files (verification pass)

Watch (1B-4):
- `Watch/App/WatchRootView.swift`, `WatchViews.swift` (only if the device pass requires)

Tests (new or extended; see section 11): `WidgetSnapshotTests`, `TierSnapshotTests`, `WidgetTimelineTests`, `WidgetGatingTests`, `IntentGatingTests`, `WatchGatingTests`, `WatchComplicationTests`, `WatchSyncTests`, `AccountStoreTests`, `StoreSafetyTests`, StoreKit session tests; new `SchemaFingerprintTests`, `EntitlementBackgroundRefreshTests`, `DeleteAllResumeTests`, `StoreCompactionTests`, `AccessibilityModifierTests`.

Not expected to change: `project.yml` and signing, `Config/Noctis.storekit` (no Family Sharing change), the PrivacyShield, HealthKit code, Coach code, the visual identity files.

---

## 11. Tests required

Principle: reuse what exists; add only what the new behaviour needs; never record a result that was not produced by a run.

Existing tests to reuse as regression guards (names from `Packages/NoctisKit/Tests/NoctisKitTests/` and `Tests/StoreTests/`):
`StoreSafetyTests` (schema version, migration harness, store damage), `StoreKitSessionTests` (24 tests covering purchase, trial, renewal, cancellation, expiry, refund, restore, Ask to Buy, billing retry, offline launch, failed verification, family-off), `FeatureGateTests`, `TierSnapshotTests`, `WidgetSnapshotTests`, `WidgetTimelineTests`, `WidgetGatingTests`, `IntentTests`, `IntentGatingTests`, `WatchSyncTests`, `WatchGatingTests`, `WatchComplicationTests`, `WatchPagesTests`, `WatchSettingsTests`, `WatchActivityTests`, `AccountStoreTests`, the four contrast test files, plus the data inventory and privacy tests from Stage 1A.

Missing tests to add, by issue:

| Issue | Test | Layer |
| --- | --- | --- |
| C01 | `effectiveTier(at:)` table: before, at, after the date; slack on and off; grace; nil date | unit |
| C01 | snapshot round trip with the new keys, old snapshots still decode, size headroom for a worst-case snapshot | unit |
| C01 | timeline contains a lock entry that flips tier; none when the date is beyond the horizon or absent | unit |
| C01, D01 | widget, intent, Watch page and complication gating with a clock moved past the date | unit |
| C01 | StoreKit: purchase, renewal, cancellation, grace each produce the right end date and flag in the snapshot | StoreKitTest |
| X01 | no code outside the seam reads the snapshot `tier` | source scan |
| X04 | a tier-only republish advances `generatedAt` and is accepted by `WatchInbox` | unit |
| C02 | background run refreshes entitlement once; failure does not fail the Health refresh; offline publishes cached state | unit |
| C03 | summary copy for billing retry without grace and for the grace state | unit |
| C04 | status read without a product fetch; offline throws are handled | StoreKitTest plus fake client |
| D02 | tier change triggers one complication transfer; same tier none; zero budget none | unit with mock session |
| D05 | delete-all while disconnected, new snapshot, reconnect: only new data | unit |
| B01 | schema fingerprint | unit |
| B02 | kill after each runner step, relaunch completes; marker clears last; epoch bumps first | unit |
| B03 | compaction shrinks file, keeps rows, skips on failed check or low space | integration |
| B04 | the three Keychain marker cases | unit |
| B05, B06 | document claims checked against the inventory; unlisted new file fails | source scan |
| A01 | button shape modifier on and off | unit with environment |
| A02, A12 | every band, tone and chart model has a non-colour descriptor and an accessibility description | table-driven unit |
| A02, A03 | probe-based UI tests with each setting on, one screen each | UI |

Layers beyond unit tests:

- **Simulator:** Accessibility Inspector audit, AX3 and AX5 screenshots, Smart Invert, Button Shapes, Differentiate Without Color, Increase Contrast, Bold Text, Reduce Transparency, Reduce Motion, widget gallery states (the existing launch flags `-forceTier`, `-widgetGalleryTier`, `-watchTier`, `-mockWatch` and the Watch paired-simulator script).
- **StoreKitTest:** everything marked "exists" or "add" in section 6.3 that does not need real timing.
- **Physical device and Sandbox/TestFlight [D]:** real expiry while terminated and the widget and complication flip; renewal while closed; billing retry and grace lengths; the real Ask to Buy sheet; restore on a second install; offline launch; kill mid delete-all; Watch Dock snapshot; disconnected deletion; VoiceOver pass; export while locked (carried from Stage 1A).
- **watchOS:** the paired-simulator script for logic; a real Watch for privacy and complication refresh.
- **Regression:** the full package suite (2,646 tests in 358 suites at Stage 1A [R]) plus the UI test classes that touch the changed screens, run from the canonical repository path with DerivedData outside the repository.

---

## 12. Risks and dependencies

- **False lock of a paying person.** The main risk of C01. Mitigated by slack when auto-renew is on, by the app's refresh on every foreground and background wake, and by the rule that the snapshot is rewritten on every renewal. Residual risk is a real-world renewal that Apple completes late; only a Sandbox or production check [D] can quantify it.
- **Silent snapshot rejection by size.** Mitigated by measurement and a headroom test (X02).
- **Tier-only republish ignored by the Watch** if `generatedAt` does not advance (X04). Mitigated by a dedicated test.
- **Background time limits.** Entitlement refresh in a background wake competes with Health work (C02). Mitigated by making it best effort and independent.
- **Compaction on an unhealthy disk** (B03): guarded by integrity check and free-space check; skipped otherwise.
- **Keychain timing** (B04): shipping it after release is riskier; the store-file guard is essential.
- **Apple documentation not verified here.** The [A] items (renewal timing, `VACUUM` transactional behaviour, Watch snapshots, complication budgets, Family Sharing irreversibility, `privacySensitive` on Watch) must be confirmed against current official documentation before the code that relies on them is merged. I will cite the page in each implementation report.
- **Physical hardware and accounts.** Sub-stage 1B-5 needs an iPhone, a paired Apple Watch and a Sandbox or TestFlight tester account. Without them those rows stay "unverified" in the ledger and the report must say so.
- **Second worktree.** Touches `HomeViewModel.swift` and `RecoveryScreen.swift`; Differentiate Without Color work on Recovery bands could touch the same area. If it does, stop and ask before editing, because the other session's uncommitted work must not be altered.
- **Remote and CI.** The repository has no remote, so nothing here is protected by CI; the backups remain the only copy beyond this Mac (owner reports a MEGA copy of the post-1A backup).

---

## 13. Owner decisions required

1. **Slack for auto-renewing plans (C01).** Proposed: 48 hours when auto-renew is on, 0 when off. Lower means a lapsed person loses widgets sooner and a late renewal might briefly lock a payer; higher means the reverse. Needed before release; implementation can start with the proposal.
2. **Family Sharing (C05).** Proposed: leave off for 1.0. Needs a deliberate decision before App Store Connect products are created.
3. **StoreKit inside the widget or Watch extensions.** Proposed: not now. The snapshot metadata approach avoids it, and watchOS support for StoreKit in these contexts is not confirmed here [A]. Revisit only if the metadata approach proves insufficient on devices.
4. **Billing-problem wording (C03).** Approve the two messages.
5. **New-phone and backup wording (B05).** Approve the statement about what moves to a new phone and what does not.
6. **Compaction (B03).** Implement the guarded version or defer it. Proposed: implement, because it is small and guarded, but deferring loses very little.
7. **Differentiate Without Color presentation (A02).** Proposed: additions appear only when the setting is on, so the default look does not change. If the owner wants the twins always visible, that is a visual change and needs approval.
8. **Verification resources.** Confirm availability of a physical iPhone, a paired Apple Watch and a Sandbox or TestFlight account for 1B-5, and who runs the manual VoiceOver and device passes.
9. **Branch.** Confirm the branch name `release/stage1b-hardening` created from `2b4e7c8`.
10. **Carried from Stage 1A, still open:** Settings wording about resting heart rate and respiratory rate (S-03), and the usage string naming five kinds above a three-kind sheet (R-04).

Items that are safe to implement without any of these: B01, B02, B04, B06, C02, C04, D02, D05, D06, A01, A03, A04 to A11, A12, X01 to X04.

---

## 14. Items to defer

- A real V2 schema or any stored-model change (no reason exists).
- Enabling Family Sharing (owner decision, unverified behaviour).
- StoreKit in widget, complication or Siri extensions.
- Server-side expiry or App Store Server Notifications (no backend, by the brief).
- Forensic-grade deletion claims or secure-delete settings.
- A Watch cover modelled on the iOS PrivacyShield (only a minimal redaction if the device pass shows exposure).
- RTL layouts (not a v1 language).
- Anything in the pre-launch audit outside Stage 1B scope: legal pages and domain, signing and App Store Connect setup, screenshots, privacy-answer sign-off, the NOCTIS-Store purchase scheme run, iOS 26.1 runs.
- A separate remote or CI setup (X-10, L-09).

---

## 15. Final Stage 1B implementation recommendation

Approve Stage 1B in the five sub-stages of section 3, in this order, each as its own reviewed commit set on a new branch from `2b4e7c8`:

1. **1B-1 Subscription expiry** (S1B-C01, C02, C03, C04, D01, D02, X01 to X04). Highest value, smallest risk, mostly covered by new unit tests plus the existing StoreKitTest suite.
2. **1B-2 Data reliability** (S1B-B01, B02, B04, B05, B06, optionally B03, D05).
3. **1B-3 Accessibility code** (S1B-A01, A02, A03, A12), starting with the read-only inventory.
4. **1B-4 Watch gaps**, only what remains after 1B-1, and the Dock privacy change only if the device pass shows exposure.
5. **1B-5 Verification pass** across accessibility, StoreKit scenarios 17 to 19, the Watch and the data path, closing ledger rows only with viewed evidence.

Safe to start immediately after approval, without waiting for owner answers: everything listed at the end of section 13. Needs an answer before release, not before coding: the slack value, billing-problem copy, new-phone wording. Not in the plan: anything on the deferral list.

What I could not establish in this phase, and the plan therefore treats as open: the real-world timing of renewals and expiry, Apple's exact behaviour for the Watch Dock snapshot and complication budgets from authoritative pages, the Keychain accessibility class, the custom-font and custom-toggle inventory, and the stale-text logic on the Watch. Each has an explicit step above that settles it before dependent code is merged.

**Waiting for approval. No implementation has been started.**
