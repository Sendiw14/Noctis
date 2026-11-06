# AUDIT_PROGRESS.md

Progress of the launch audit in `~/Downloads/NOCTIS_LAUNCH_AUDIT.md`. If a session ends, resume from "Next".

Started 2026-11-03. Tree audited: branch `release/stage1b-hardening`, HEAD `2b4e7c8`, plus uncommitted Stage 1B work. The audit has changed no app code, config or git history; it added only this file and `LAUNCH_AUDIT_REPORT.md`.

## Status

| Phase | Status |
| --- | --- |
| 0 Recon | Done. UI tests and Thread Sanitizer not run (killed by another session's `pkill -f xcodebuild`) |
| NOCTIS-specific checks | Done, except anything that needs a device |
| 1-20 | First pass done; status per phase in the report, section 4 |
| Report | Written: `LAUNCH_AUDIT_REPORT.md`. Verdict NO-GO |
| Fixes | Not started. **Waiting for owner approval** |

## Next

1. Owner reads the report and approves or changes the fix list and the structure proposal (section 8).
2. Confirm no other session is editing this checkout, then commit Stage 1B.
3. Re-run the baseline, plus the UI subset and Thread Sanitizer. Update the report.
4. Fixes in the agreed order: Phase 18, Phase 17 PRE-LAUNCH, Phase 19, then BLOCKER and HIGH.

## Notes for whoever resumes

- A second Claude session edited this checkout during the audit (`PreferencesTests.swift`, `NotificationCoordinator.swift`). Check `git status` before trusting any number.
- Do not run `xcodegen generate` in the repo without checking the result: it rewrites the entitlement and Info.plist files. Use a copy.
- Periphery is not installed. Installing it needs the owner's OK.
- Only iOS 27 and watchOS 27 simulators are installed, so the iOS 26.1 minimum cannot be run here.
