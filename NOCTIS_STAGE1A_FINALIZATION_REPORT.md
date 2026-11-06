# NOCTIS_STAGE1A_FINALIZATION_REPORT.md

Stage 1A finalization: one controlled local commit of the reviewed implementation. Nothing was pushed (the repository has no remote and the branch has no upstream). Written 2026-11-02.

## Result

**Committed locally as `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b`** on `release/prelaunch-hardening`: `feat: harden NOCTIS pre-launch privacy and HealthKit flows`.

| Item | Value |
| --- | --- |
| Starting commit | `d0f0f28c8494d055eca0962470f393f12a34e941` (matched the expected value) |
| New commit | `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b` (parent `d0f0f28…`) |
| Branch | `release/prelaunch-hardening` (not pushed, no upstream, no remote) |
| Files in the commit | 25: 21 modified, 4 added |
| Size | 25 files changed, 645 insertions, 24 deletions |

**One correction made during finalization.** The first version of the commit (`0befc81`) said "28 tests added"; the correct number is 27 (13 + 6 + 8, and the full suite grew from 2,619 to 2,646). I amended only the message of that unpushed commit; the tree was unchanged. `0befc81` is no longer on the branch (it remains in the reflog).

## 1. Pre-commit verification (all passed)

- Branch `release/prelaunch-hardening`, HEAD equal to the expected starting commit, nothing staged, 0 stashes, no remote.
- Status before staging: exactly the 21 modified tracked files, the 4 new source/test files, and 6 untracked report/patch files (not staged).
- **S-01 corrected:** the old text ("Not run against real HealthKit") is gone from `Docs/PRIVACY_REPORT.md`; the new item names `restingHeartRateIfAsked` and the real-HealthKit checks. **S-02 corrected:** the comment on `canRequestAccess` says "at least one of the five kinds".
- **Matches the approved patch:** a fresh regeneration of the patch has the same SHA-256 as `NOCTIS_STAGE1A_SOURCE_DIFF.patch`, and the patch's 25-file list equals the working tree's change list.

## 2. What was staged and what was not

Staged by explicit file name only (no `git add .` or `-A`): the 25 files listed below. After staging, the staged list was identical to the patch's list, `git diff --cached --check` exited 0, and all four new files were included.

**Not staged, left untracked and unchanged:** `APP_STORE_PRE_LAUNCH_AUDIT.md`, `NOCTIS_BACKUP_REPORT.md`, `NOCTIS_STAGE1A_IMPLEMENTATION_REPORT.md`, `NOCTIS_STAGE1A_REVIEW_REPORT.md`, `NOCTIS_STAGE1A_SECOND_REVIEW_REPORT.md`, `NOCTIS_STAGE1A_SOURCE_DIFF.patch`, and this report. No generated build artifacts exist in the repository.

## 3. Files committed (25)

Added (4):
- `Packages/NoctisKit/Sources/AppRoot/PrivacyShield.swift`
- `Packages/NoctisKit/Tests/NoctisKitTests/ExportProtectionTests.swift`
- `Packages/NoctisKit/Tests/NoctisKitTests/HealthAuthorizationFlowTests.swift`
- `Packages/NoctisKit/Tests/NoctisKitTests/PrivacyShieldTests.swift`

Modified (21):
- `App/NoctisApp.swift`
- `Docs/DEVICE_TEST_CHECKLIST.md`, `Docs/PRIVACY_REPORT.md`, `Docs/site/privacy.html`, `Docs/store/APP_STORE_LISTING.md`, `Docs/store/SUBMIT_CHECKLIST.md`
- `Packages/NoctisKit/Sources/AppRoot/DataWiring.swift`
- `Packages/NoctisKit/Sources/HealthProviding/HealthDataProviding.swift`, `HealthKitProvider.swift`, `HealthModels.swift`, `Mock/MockHealthKitProvider.swift`
- `Packages/NoctisKit/Sources/NoctisCore/DataExport.swift`, `DataManager.swift`, `HealthDataStatus.swift`, `HomeRepository.swift`, `InsightsRepository.swift`, `RecoveryRepository.swift`, `ReviewRepository.swift`
- `Packages/NoctisKit/Sources/OnboardingFeature/HealthScreen.swift`
- `Packages/NoctisKit/Sources/ProfileFeature/SettingsContent.swift`, `SettingsPages.swift`

**Content check after committing:** the committed tree (`git archive HEAD`) is identical to the approved patch applied to a clean `git archive` of the starting commit.

## 4. Tests and build evidence (carried from the approved work; nothing was rebuilt in this stage, no code changed)

All on the iPhone 18 Pro, iOS 27.0 simulator (24A434), Xcode 27.0 (27A266a), DerivedData outside the repository. The commit's tree equals the tree these ran on, except for the two documentation/comment corrections (S-01, S-02), after which the affected suites were re-run.

- Full package suite after the rework: **2,646 tests in 358 suites passed** (629.6 s). The baseline was 2,619 in 355.
- After S-01 and S-02: **67 tests in 10 suites passed** (privacy manifest and enforcement, privacy-words, data inventory, health flow, health behaviour, health step, source hygiene, settings, profile).
- Second-review targeted run: 61 tests in 8 suites passed.
- Release build (`generic/platform=iOS`, unsigned): **BUILD SUCCEEDED, 0 warnings**; signed Debug simulator build: succeeded, 0 warnings.
- `scripts/release_symbol_check.py`: **exit 0**, 7 binaries, 0 hits.
- UI tests `HealthQATests`, `OnboardingQATests`, `RecoveryQATests`, signed ad hoc: **39 of 39 passed**.
- Real HealthKit on the simulator: three core kinds allowed → empty state; declined → empty state; Health skipped → "Connect Apple Health".
- `git diff --check` and `git diff --cached --check`: clean.

## 5. Git status after the commit

Branch `release/prelaunch-hardening`, HEAD `2b4e7c8`. No staged or unstaged changes. Untracked: the six report/patch files listed in section 2 (plus this report). Stashes: 0.

## 6. Second worktree (not touched)

`/Users/sendiwkithnada/Documents/Noctis/.claude/worktrees/charming-liskov-749f7b`, branch `claude/charming-liskov-749f7b` at `f6fb3c8`. Its six modified files are unchanged: `APP_RULES.md`, `HomeViewModel.swift`, `RecoveryScreen.swift`, `HomeScreenBuilderTests.swift`, `RecoveryScreenTests.swift`, `UITests/HomePerformanceQATests.swift`. The hash of its `git diff --binary` is `83a81df85233c1d2` before and after, identical to the hash of the patch saved in the backup.

## 7. Backup verification

`/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-backup-20261101-225518/` still exists with permissions unchanged: all 933 SHA-256 checksums verify (0 failures), the report copy's checksum verifies, and `git bundle verify` reports the bundle okay (6 refs). The backup predates the commit, so it does not contain it; it is a restore point for the state before Stage 1A. It is on the same disk as the repository.

## 8. Remaining issues (unchanged, none introduced by this stage)

- **Device verification still required:** the keyboard drawn above the privacy cover (R-03); the cover on transient inactive moments and multiple scenes (R-06, R-07); export while the iPhone is locked, the file protection class, and the system's copy of the shared file (R-08, R-09); Coach on an Apple Intelligence iPhone and on one without; the HealthKit flow with real Health data; iOS 26.1 (never run).
- **Owner decisions:** whether Settings' note should say that granting resting heart rate and respiratory rate refines Recovery (the same night scored 67 without resting heart rate and 70 with it in the mock probe), or whether onboarding should ask for all five (S-03); the usage string naming five kinds above a three-kind sheet (R-04).
- **Not run:** the NOCTIS-Store purchase scheme.
- **Source safety:** the repository still has no remote; the commit exists only on this Mac (and not in the backup). Copy the backup and the repository somewhere off this device when you are ready; nothing was uploaded.
- Everything else in the pre-launch audit remains open: legal pages and domain, signing and App Store Connect setup, screenshots, privacy-answer sign-off.

Stage 1A is finalized locally. Stage 1B has not been started. Nothing was pushed.
