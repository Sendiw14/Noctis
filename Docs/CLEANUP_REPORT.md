# CLEANUP_REPORT.md

What the cleanup removed, with numbers. Two passes: the code pass on branch `cleanup/release` (QA-185) and the disk pass on 2026-11-01 (QA-191). Sizes are from `du` on this Mac.

## Code pass (QA-185)

- Removed 16 unreferenced types and about 40 unreferenced members (657 lines), 5 unused `@Environment` values and 3 redundant imports.
- Removed 775 MB of local build folders.
- Not done, with the reason: files over 400 lines were not split (41 shipped files before, 45 after swift-format). They are per-screen view collections whose private helpers would have to
  become internal, and many source-text tests read them by name. SwiftLint flagged about 190 unused imports, but removing them broke the build in DesignSystem, so only the 3 provably safe ones went.
  Two parallel card and scaffold families remain (onboarding's fixed light palette against the main app's adaptive tokens). User-facing text is in five module catalogs, not one (QA-061).
- Five force operations stay in shipped code, each on a constant (QA-186).

## Disk pass (2026-11-01, outside the repository)

| What | Before | After | Note |
| --- | --- | --- | --- |
| `~/Library/Developer/CoreSimulator/Devices` | 119 GB | 15 GB | Ten QA simulators deleted (nine "QA" and "PlusQA" devices and "QA 17 Pro"). The stock iPhone 17, iPhone 18 Pro and five Apple Watch simulators stay. |
| `~/qa-work` | 43 GB | 12 GB | The old `dd-*` build folders deleted. The screenshots, contact sheets and run records the ledger cites stay. |
| `DerivedData` for this project | about 2.5 GB | 2.1 GB | Cleared once to fix QA-190, then rebuilt by the test run. Safe to delete any time. |

The repository itself is 16 MB and needed nothing. A second DerivedData folder in the same place belongs to another project and was not touched.

## What this means for the next QA run

The QA scripts read `~/qa-work/devices.env`, which still names the deleted simulators. Create the simulators again (the ledger header lists the models: 17 Pro, 17 Pro Max, SE),
then update that file. Nothing in the repository needs to change.

## Still large, not touched

- `~/qa-work` at 12 GB: screenshots and matrix runs. Delete the folders you no longer need to look at; `Docs/qa` and `Docs/evidence` in the repository keep the records.
