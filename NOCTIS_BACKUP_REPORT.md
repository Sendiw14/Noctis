# NOCTIS_BACKUP_REPORT.md

Stage 0: source code protection and backup. Backup-only: no source, configuration or Git state was changed, nothing was committed, pushed, stashed, reset, checked out or deleted. The only things written were the backup folder (new, outside the project), scratch restore tests in the session scratchpad, and this report.

Date: 2026-11-01, 22:55 to 22:57 (+0530).

## Result

**The project is protected locally: every verification check passed.** One limit matters: the backup is on the same Mac and disk as the project, and the repository has no remote. It protects against accidental changes, bad commits and deleted branches. It does **not** protect against loss of this disk or Mac. See "What this backup does not cover".

## 1. Repository inspected

| Item | Finding |
| --- | --- |
| Repository root | `/Users/sendiwkithnada/Documents/Noctis` |
| Current branch / commit | `cleanup/release` at `d0f0f28c8494d055eca0962470f393f12a34e941` |
| Local branches (4) | `cleanup/release` d0f0f28 (checked out), `main` c4b213b, `onboarding-final-pass` e8a964b, `claude/charming-liskov-749f7b` f6fb3c8 (checked out in the second worktree) |
| Tags | 0 |
| Stashes | 0 |
| Remotes | **0** |
| Worktrees (2) | main checkout above; `/Users/sendiwkithnada/Documents/Noctis/.claude/worktrees/charming-liskov-749f7b` on branch `claude/charming-liskov-749f7b` |
| Staged changes | none, in either worktree |
| Uncommitted tracked changes | main checkout: none. Worktree `charming-liskov-749f7b`: 6 modified files, +106 / -9 lines (`APP_RULES.md`, `HomeViewModel.swift`, `RecoveryScreen.swift`, `HomeScreenBuilderTests.swift`, `RecoveryScreenTests.swift`, `UITests/HomePerformanceQATests.swift`) |
| Untracked files | main checkout: 1 (`APP_STORE_PRE_LAUNCH_AUDIT.md`, the audit report written earlier in this session). Worktree: none |
| Ignored files | main: 6 `.DS_Store` files and the nested worktree folder `.claude/worktrees/` (ignored through `.git/info/exclude`). Worktree: none |
| Repository size | `.git` 4.2 MB (3.19 MiB packed, 70 loose objects 580 KiB); working tree 17 MB including the nested worktree (699 files in the main tree, 209 in the second worktree) |
| Important files | `project.yml`, `Noctis.xcodeproj/project.pbxproj`, `Packages/NoctisKit/Package.swift`, `Config/*.entitlements`, `Config/Noctis.storekit`, `App/Info.plist`, `README.md`, `Docs/` |

The second worktree was **inspected read-only** (`git --no-optional-locks status`, `diff`, plain file copy). Nothing in it was modified, staged, stashed or checked out. It belongs to another session's work; its uncommitted changes were copied, not touched.

## 2. Backup location and contents

**Destination:** `/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-backup-20261101-225518/` (new folder; created without `-p` so an existing backup could never be overwritten; no earlier backup existed).
**Size:** 20 MB, 936 files (933 checksummed files, `SHA256SUMS.txt`, and the report copy with its checksum). Permissions: owner-only (`drwx------`, files `-rw-------`); 0 entries are readable by group or others.

| Path in backup | What it holds |
| --- | --- |
| `git/noctis-all-refs.bundle` (3.2 MB) | Git bundle of **all refs**: the 4 branches, HEAD, and the other worktree's HEAD; complete history, no prerequisites |
| `git/dot-git-raw.tar` (4.6 MB) | Raw copy of the whole `.git` directory: objects, config, reflogs, worktree administration (`.git/worktrees/charming-liskov-749f7b`), hooks |
| `worktrees/main/` (11 MB) | Full working tree of the main checkout: tracked files, the untracked audit report, the ignored `.DS_Store` files |
| `worktrees/claude__charming-liskov-749f7b/` (2.2 MB) | Full working tree of the second worktree, **including its 6 uncommitted modifications** and its `.git` pointer file |
| `patches/` | `main-staged.patch`, `main-unstaged.patch` (both empty: no tracked changes), `claude__charming-liskov-749f7b-unstaged.patch` (14,259 bytes, the 6 modified files), `...-staged.patch` (empty) |
| `metadata/` | `backup-info.txt` (date, host, git version), `refs.txt`, `branches.txt`, `worktrees.txt`, `remotes.txt`, `stashes.txt`, `tags.txt`, `git-config.txt`, `log-all-graph.txt`, `count-objects.txt`, per-worktree `status-*.txt`, `untracked-*.txt`, `ignored-*.txt`, live and snapshot `inventory-*.txt`, `verification.txt` |
| `SHA256SUMS.txt` | SHA-256 of the other 933 files |
| `NOCTIS_BACKUP_REPORT.md`, `NOCTIS_BACKUP_REPORT.sha256` | A copy of this report and its own checksum. The report was written after the snapshot, so it is **not** in `worktrees/main/` or `SHA256SUMS.txt`; the live repository now has it as a second untracked file |

## 3. What was preserved

- **Git history:** all commits and branches (bundle + raw `.git`). There are no tags or stashes to preserve.
- **Uncommitted work:** the second worktree's 6 modified files are in its snapshot, in the patch file, and (via the raw `.git` and the snapshot) restorable. The main checkout has no uncommitted tracked changes; its one untracked file (`APP_STORE_PRE_LAUNCH_AUDIT.md`) is in `worktrees/main/`.
- **Untracked and ignored files:** accounted for in `metadata/untracked-*.txt` and `ignored-*.txt` and present in the snapshots. Ignored `.DS_Store` files were copied too.
- **Metadata:** branch names, commit hashes, worktree locations, per-worktree status, remote configuration (none), backup date.

## 4. Exclusions (all documented)

| Excluded | Why |
| --- | --- |
| `.git/` inside `worktrees/main/` | Saved separately and completely as the bundle and `dot-git-raw.tar`; copying it twice adds nothing |
| `.claude/worktrees/` inside `worktrees/main/` | It is the second worktree, backed up in its own snapshot |
| Build products, DerivedData, archives | None exist inside the repository (they were never written there), so nothing had to be left out for size |
| Anything outside the repository | Not part of the project (the audit scratchpad, simulators, DerivedData) |

No file in either working tree was left out.

## 5. Sensitive files

- A name search of both trees for `.env*`, `*.p8`, `*.p12`, `*.pem`, `*.cer`, `*.mobileprovision`, `*.certSigningRequest`, `Secrets.xcconfig`, keychains and SSH keys found **nothing**. The project holds no signing material or credentials (no signing team is set; `.gitignore` already excludes such files). This is a filename search, not a content scan.
- The backup is **local only**: nothing was uploaded, no remote was created, no public repository was created.
- Folder and file permissions are owner-only. Two helper files were created with looser permissions and tightened (`chmod go-rwx`) before the final checksum run.

## 6. Verification (all passed)

| Check | Result |
| --- | --- |
| Bundle integrity | `git bundle verify`: "records a complete history", sha1; all 4 branch refs and HEAD listed in the bundle with the expected hashes |
| Refs vs live repository | Bundle refs, raw-`.git` refs and `metadata/refs.txt` are identical to the live repository's refs |
| Restore test from bundle | Cloned into scratch space; `git fsck --full` reported no errors; 4 branches present with correct hashes; the documented restore procedure (below) was run end to end |
| Restore test from raw `.git` | Extracted into scratch space; `git fsck --full` reported no errors (only the usual dangling trees); same 4 refs |
| Main snapshot vs live tree | `diff -rq` (excluding `.git` and the nested worktree): **identical**, 0 differences, 699 files |
| Second-worktree snapshot vs live tree | `diff -rq`: **identical**, 0 differences, 209 files |
| File inventories | Snapshot and live file lists identical for both trees (699 and 209). The two directories that exist only as empty folders (`.swiftpm`, `xcshareddata`) are copied too |
| Uncommitted work preserved | Patch applied cleanly on a fresh checkout of the worktree's commit `f6fb3c8` (in the scratch clone, not the real repository); the result matches the snapshot file for file |
| Main-tree changes | staged and unstaged patches both empty, matching `git status` (clean apart from the one untracked file) |
| SHA-256 | `SHA256SUMS.txt` generated for 933 files; `shasum -a 256 -c` run twice: **933 OK, 0 failed** |
| Important files located | In `worktrees/main/`: `project.yml`, `Noctis.xcodeproj/project.pbxproj`, `Packages/NoctisKit/Package.swift`, `Config/Noctis.entitlements`, `Config/Noctis.storekit`, `App/Info.plist`, `App/NoctisApp.swift`, `README.md`, `Docs/APP_RULES.md`, `APP_STORE_PRE_LAUNCH_AUDIT.md`. In the worktree snapshot: `project.yml`, `project.pbxproj`, `APP_RULES.md`, `RecoveryScreen.swift` |
| Live repository after the backup | Unchanged: branch `cleanup/release`, HEAD `d0f0f28`, 2 worktrees, 0 stashes, status shows only the one untracked file; second worktree still shows its 6 modified files |

Failures: **none.** One test statement was wrong the first time (a shell quoting error wrote empty metadata files); it was caught and the metadata and patches were regenerated before checksums were computed. Nothing in the repository was affected.

## 7. What this backup does not cover

- **No second copy on another device.** The project, the other worktree and this backup are all on `/System/Volumes/Data` of this Mac. A disk failure or loss of the Mac would lose all of them. Copy the backup folder to an external drive or a private location you control. Because it holds source code, keep it private; do not put it in a public repository.
- **No remote exists** for the repository, so there is no hosted history. Adding one (private only) is a decision for you, not part of this stage.
- **Time Machine or other system backups** were not checked.
- **The scratchpad** from earlier audit work (`/private/tmp/claude-501/.../scratchpad`) holds build products and a source snapshot; it is temporary and is not part of this backup.

## 8. How to restore

All commands read from the backup and write somewhere new. Replace `$B` with the backup path.

```bash
B=/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-backup-20261101-225518
cd "$B" && shasum -a 256 -c SHA256SUMS.txt        # every line must say OK
```

**A. Restore the whole Git history into a new folder** (tested):

```bash
git clone "$B/git/noctis-all-refs.bundle" ~/Documents/NOCTIS-restored
cd ~/Documents/NOCTIS-restored
for b in $(git branch -r | grep -v HEAD | sed 's#^ *origin/##'); do git branch --track "$b" "origin/$b" 2>/dev/null; done
git remote remove origin          # the bundle is not a real remote
git branch -vv                    # 4 branches, HEAD on cleanup/release
```

**B. Restore the exact folder as it was on 2026-11-01** (history, config and worktree administration included):

```bash
mkdir ~/Documents/NOCTIS-restored-raw && cd ~/Documents/NOCTIS-restored-raw
tar -xf "$B/git/dot-git-raw.tar"                       # recreates .git
cp -Rp "$B/worktrees/main/." .                         # all files, including the untracked audit report
git status                                             # should show only APP_STORE_PRE_LAUNCH_AUDIT.md as untracked
```

The `.git` copy still records the second worktree at its original path (`.../Noctis/.claude/worktrees/charming-liskov-749f7b`). To bring it back, either restore B into the original `Documents/Noctis` location and copy `worktrees/claude__charming-liskov-749f7b/.` into `.claude/worktrees/charming-liskov-749f7b/`, or run `git worktree prune` in the restored copy and recreate the branch with `git worktree add` (below).

**C. Recover only the other session's uncommitted work:**

```bash
cd ~/Documents/NOCTIS-restored
git worktree add ../charming-liskov-restored claude/charming-liskov-749f7b
cd ../charming-liskov-restored
git apply "$B/patches/claude__charming-liskov-749f7b-unstaged.patch"   # the 6 modified files
```
or copy the finished files straight from `"$B/worktrees/claude__charming-liskov-749f7b/"`.

**D. Restore one file:** copy it from `"$B/worktrees/main/<path>"`.

## 9. Final confirmation

The entire NOCTIS source project, all four branches, both worktrees and the second worktree's uncommitted changes, is **successfully protected in a verified local backup** (933 of 933 checksums good, snapshots byte-identical to the live trees, bundle and raw `.git` restore tests clean). It is **not yet protected against loss of this Mac or disk**; that needs one more copy somewhere you choose.

Stage 0 stops here. No implementation was started.
