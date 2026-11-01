# RELEASE_READINESS.md

The release audit, item by item. Written 2026-11-01 from `QA_LEDGER.md`, `QA_REPORT.md`, `PRIVACY_REPORT.md` and `POST_LAUNCH.md`. A verdict of READY has evidence behind it in
those documents; anything without evidence is UNVERIFIED or BLOCKED, with the reason. Nothing here was re-run for this document unless the row says so.

## Verdict

**Ready for TestFlight. Not ready for App Store submission** until the BLOCKED rows below are closed. None of them is a code change.

## Items

| Item | Verdict | What is needed |
| --- | --- | --- |
| Features built and reachable | READY | `ROADMAP.md` is empty and `NothingUnbuiltIsReachableTests` holds it. |
| Package unit suite | READY | 2542 tests in 342 suites passed on the final tree of QA part 4 (`QA_REPORT.md` section 2). |
| Purchase tests (`NOCTIS-Store`) | READY with a note | Intermittent in QA-182. Fixed in QA-188 (polling waits): 3 of 3 runs, 24 tests, 1 known issue. A small sample; run the scheme a few more times before relying on it. |
| Debug scaffolding absent from Release | READY | `scripts/release_symbol_check.py` exit 0 (`Docs/evidence/release_symbol_check.txt`, QA-183). |
| Privacy manifest and data inventory | READY | Held by `DataInventoryTests` and `PrivacyManifestTests`. |
| Privacy report and App Privacy answers | OWNER | `PRIVACY_REPORT.md` is a draft. The owner reads every sentence; the published policy, the report, the manifest, the App Store Connect answers and the Privacy Center must say the same thing. |
| Terms of Use, Privacy Policy and support address | **BLOCKED** | QA-004, QA-180. `noctis.app` redirects to a domain-sale page and `/terms`, `/privacy` return 404. Publish real pages and a working inbox, then change `StoreLegalLinks` (`StoreConstants.swift`). App Store Connect needs a Privacy Policy URL. |
| Signing team, bundle IDs, App Group | **BLOCKED** | No team is set. Register the four bundle IDs and the App Group listed in `README.md`, then set the team on every target. |
| Signed archive and App Store validation | UNVERIFIED | QA-027. Needs the signing team. |
| iOS 26.1 to 26.x at run time | UNVERIFIED | QA-020. QA ran on iOS 27. Run the app on an iOS 26.1 simulator or device before declaring the minimum. |
| Real iPhone, real Apple Watch, real purchase and expiry | UNVERIFIED | `DEVICE_TEST_CHECKLIST.md` lists what to run. The simulator numbers in QA-122 are not device numbers. |
| Plan expiry on widgets, Watch and intents while the app is not running | KNOWN GAP | Listed in `POST_LAUNCH.md`. Needs a real device and a real expiry. |
| Large text, right-to-left and pseudolanguage layouts | PARTLY VERIFIED | Fixes are in source; the open minor rows in `QA_LEDGER.md` stay OPEN until re-photographed. `QA_COVERAGE.md` counts what is unverified. |
| App Store metadata, screenshots, age rating, review notes | NOT STARTED | Prepared by the owner in App Store Connect. The review notes should say the app is not a medical device and reads Health data read-only. |

## Order that unblocks fastest

1. Domain, legal pages, support inbox. Change the three constants, run `SettingsTests` and `StoreTests`.
2. Signing team and bundle IDs, then an archive and App Store validation.
3. The device pass in `DEVICE_TEST_CHECKLIST.md`.
4. Owner sign-off on `PRIVACY_REPORT.md`, then the App Privacy answers.
