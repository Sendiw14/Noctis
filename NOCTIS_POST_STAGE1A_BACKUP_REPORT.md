# NOCTIS_POST_STAGE1A_BACKUP_REPORT.md

Post-Stage-1A backup of the NOCTIS repository. Backup-only: no source, configuration or Git state was changed; nothing was committed, pushed, stashed, reset, checked out or cleaned; the second worktree was only read; no remote was created; no existing backup was modified or deleted. Written 2026-11-02.

## Result

**The post-Stage-1A backup is complete and every verification passed.**

| Item | Value |
| --- | --- |
| Backup folder | `/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-post-stage1A-20261102/` (new; created without `-p`, so it could not overwrite anything) |
| Size | 21 MB, 947 files (946 checksummed, plus the manifest `SHA256SUMS.txt`); this report and its checksum are added beside them |
| Permissions | owner-only (`drwx------`, files `-rw-------`); 0 entries readable by group or others, 0 not owned by the current user |
| Repository state at backup | branch `release/prelaunch-hardening`, HEAD `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b` (matched the expected value), 0 stashes, 0 remotes, nothing modified or staged, 7 untracked report/patch files |

## 1. Contents

| Path in backup | What it holds |
| --- | --- |
| `git/noctis-all-refs.bundle` (3.2 MB) | Bundle of all refs: 5 branches (`claude/charming-liskov-749f7b`, `cleanup/release`, `main`, `onboarding-final-pass`, `release/prelaunch-hardening`), HEAD, and the second worktree's HEAD; complete history |
| `git/dot-git-raw.tar` (4.9 MB) | Raw copy of the whole `.git` directory: objects, config, reflogs, worktree administration (`.git/worktrees/charming-liskov-749f7b`), hooks |
| `worktrees/main/` (11 MB, 709 files) | The main working tree: tracked files at the Stage 1A commit, and the 7 untracked files (audit report, backup report, implementation report, first and second review reports, finalization report, source patch) |
| `worktrees/claude__charming-liskov-749f7b/` (2.2 MB, 209 files) | The second worktree, including its six uncommitted changes and its `.git` pointer |
| `patches/` | `claude__charming-liskov-749f7b-unstaged.patch` (14,259 bytes, the six modified files), the staged patches (all empty: nothing is staged anywhere), `stage1A-commit-2b4e7c8.patch` (73,139 bytes, the commit as a patch) |
| `metadata/` | `backup-info.txt`, `refs.txt`, `branches.txt`, `worktrees.txt`, `remotes.txt`, `stashes.txt`, `tags.txt`, `git-config.txt`, `count-objects.txt`, `log-all-graph.txt`, **`reflog-all.txt`** and `reflog-head.txt`, per-worktree status, untracked and ignored lists, live file inventories, `verification.txt` |
| `SHA256SUMS.txt` | SHA-256 of the 946 other files |

**Exclusions (documented):** inside `worktrees/main/`, the `.git` directory (saved whole in the bundle and `dot-git-raw.tar`) and `.claude/worktrees/` (saved as its own snapshot). No file was otherwise left out; the repository contains no build products or credentials (a filename search at the first backup found none, and nothing new of that kind was added). This report, written after the snapshot, is **not** in `worktrees/main/` or the manifest; its copy and its own checksum sit at the backup root.

## 2. Verification results

| # | Check | Result |
| --- | --- | --- |
| 1 | Bundle integrity | `git bundle verify`: "okay"; 7 refs listed |
| 2 | Branch references | All 5 live branches are in the bundle with identical hashes; `release/prelaunch-hardening` = `2b4e7c8f48aaa6b94d56a366fcaa286e186d120b`; the bundle's HEAD is the same commit |
| 3 | Restore from the bundle into a scratch folder | Cloned and fetched all branches; `git fsck --full` reported no errors; the five refs match; commit `2b4e7c8` is a commit object (`cat-file -t`) and `release/prelaunch-hardening` resolves to it; log shows `2b4e7c8 feat: harden NOCTIS pre-launch privacy and HealthKit flows` on top of `d0f0f28` |
| 4 | Restore from the raw `.git` into scratch | `git fsck --full`: no errors (only the usual dangling objects, including the pre-amend commit); the five refs match; HEAD `2b4e7c8` on `release/prelaunch-hardening`; worktree administration present |
| 5 | Working-tree snapshots vs the live trees | `diff -rq` main (excluding `.git` and the nested worktree): **identical**; second worktree: **identical**; file inventories identical (709 and 209 files) |
| 6 | Untracked reports | All seven are in the main snapshot and byte-identical to the live files (checked with `cmp`) |
| 7 | Full restore | Raw `.git` plus the main snapshot restored into scratch: branch `release/prelaunch-hardening`, HEAD `2b4e7c8`, and `git status` **identical to the live status** (7 untracked files, 0 modified), i.e. a restore is a faithful copy |
| 8 | Uncommitted changes in the second worktree | The patch applies cleanly to a fresh checkout of its commit `f6fb3c8` (in the scratch clone) and the result equals the worktree snapshot file for file; the snapshot status lists the 6 modified files |
| 9 | SHA-256 | `SHA256SUMS.txt` generated for 946 files; `shasum -a 256 -c`: **946 OK, 0 failed** |
| 10 | Second worktree unchanged | Its `git diff --binary` hash is `83a81df85233c1d2` now, in the new backup patch, and in the original backup's patch: all identical; its six modified files, branch `claude/charming-liskov-749f7b` and HEAD `f6fb3c8` are unchanged |
| 11 | Original backup untouched | `/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-backup-20261101-225518/`: all 933 checksums verify, 0 failures, report checksum OK, 939 files; no change to it |
| 12 | Repository after the backup | Same branch and HEAD, nothing modified or staged, 0 stashes, 0 remotes |

## 3. Problems met while making the backup (both mine, both fixed, no data affected)

- The first checksum run reported one mismatch: I had appended a log line to `metadata/verification.txt` after taking the checksums. I finished the log first and regenerated the manifest.
- The regenerated manifest then listed itself (the empty manifest file existed when `find` ran) and failed its own check. I regenerated it excluding itself. The final run is **946 of 946 OK**.

## 4. Restore instructions

All commands read from the backup and write somewhere new. `B=/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-post-stage1A-20261102`.

```bash
B=/Users/sendiwkithnada/Backups/NOCTIS/NOCTIS-post-stage1A-20261102
cd "$B" && shasum -a 256 -c SHA256SUMS.txt        # every line must say OK
```

**A. Restore the history into a new folder** (tested in step 3):
```bash
git clone "$B/git/noctis-all-refs.bundle" ~/Documents/NOCTIS-restored
cd ~/Documents/NOCTIS-restored
for b in $(git branch -r | grep -v HEAD | sed 's#^ *origin/##'); do git branch --track "$b" "origin/$b" 2>/dev/null; done
git remote remove origin
git branch -vv      # 5 branches; release/prelaunch-hardening at 2b4e7c8
```

**B. Restore the exact folder as it is now** (tested in step 7):
```bash
mkdir ~/Documents/NOCTIS-restored-raw && cd ~/Documents/NOCTIS-restored-raw
tar -xf "$B/git/dot-git-raw.tar"
cp -Rp "$B/worktrees/main/." .
git status          # only the 7 untracked report/patch files
```

**C. Recover only the second worktree's uncommitted work:** `git worktree add ../restored claude/charming-liskov-749f7b`, then `git apply "$B/patches/claude__charming-liskov-749f7b-unstaged.patch"`, or copy files from `"$B/worktrees/claude__charming-liskov-749f7b/"`. The `.git` copy keeps the worktree's original path; either restore into the original location or run `git worktree prune` first.

**D. One file:** copy it from `"$B/worktrees/main/<path>"`.

## 5. Limits

- **Same disk, no second copy.** The project, the second worktree and both backups are on this Mac's internal disk. A disk failure or loss of the Mac would lose all of them. Copy `~/Backups/NOCTIS` somewhere you control (an external drive); keep it private. Nothing was uploaded.
- The repository has no remote. The Stage 1A commit exists in this repository and in this backup only.
- The second worktree is another session's work; it was copied and read, never changed.

Backup creation and verification are complete. Nothing was committed or pushed, and Stage 1B has not been started.
