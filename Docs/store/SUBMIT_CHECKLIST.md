# SUBMIT_CHECKLIST.md

The steps from this repository to "Submit for Review", in order. Everything that can be done without your Apple account, your domain or a real device is already done and is listed under
"Already done". What is left needs you, and each step says why. Written 2026-11-01.

## Already done (evidence in the documents named)

- Features built and reachable; no "coming soon" anywhere (`ROADMAP.md`, `NothingUnbuiltIsReachableTests`).
- Unit suite: 2619 tests in 355 suites pass (`QA_REPORT.md`). Purchase tests: 3 of 3 runs pass (QA-188).
- Release build succeeds with 0 warnings; 0 debug-only names in 7 binaries (`scripts/release_symbol_check.py`).
- Privacy manifests for all five targets, a tested data inventory, no networking code, read-only Health.
- App icon is 1024 x 1024 with no transparency, light and dark.
- Usage descriptions, export compliance (`ITSAppUsesNonExemptEncryption` NO), portrait only, deployment target 26.1.
- Listing text, review notes, subscription table, age-rating and privacy guidance: `Docs/store/APP_STORE_LISTING.md`.
- Draft privacy policy, terms and support pages: `Docs/site/`.

## 1. Publish the legal pages (blocks submission: QA-004, QA-180)

1. Get a domain you control. `noctis.app` redirects to a domain-sale page and is not yours unless you buy it.
2. Open `Docs/site/*.html` and replace every `[[SUPPORT_EMAIL]]`, `[[OWNER_NAME]]` and `[[DATE]]`. Read the privacy policy and the terms yourself: they are drafts, not legal advice.
3. Check none is left: `grep -rn "\[\[" Docs/site` must print nothing.
4. Host the folder anywhere that serves static files over https (GitHub Pages, Netlify, Cloudflare Pages). The three pages must be reachable without a login.
5. Set a mailbox for the support address and send yourself a test message.
6. Change the three constants in `Packages/NoctisKit/Sources/NoctisCore/Store/StoreConstants.swift` (`terms`, `privacy`, `supportEmail`) to the real addresses, then run `SettingsTests` and the `NOCTIS-Store` scheme.
   Terms can stay Apple's standard agreement (`appleStandardTerms`) if you prefer; then `terms.html` is an addition, not a replacement.

## 2. Apple Developer account

1. Register the App IDs and the App Group:

   | Target | Bundle ID |
   | --- | --- |
   | NOCTIS (iPhone) | `com.noctis.app` |
   | Widgets, controls, Live Activity | `com.noctis.app.widgets` |
   | Alarm widget extension | `com.noctis.app.alarm` |
   | Watch app | `com.noctis.app.watchkitapp` |
   | Watch complications | `com.noctis.app.watchkitapp.widgets` |
   | App Group | `group.com.noctis.app` |

2. Capabilities: HealthKit (with background delivery), Sign in with Apple, App Groups on the four targets whose entitlements list the group. AlarmKit and Live Activities need no capability, only the usage
   description and the Info.plist key that are already in place.
3. If you choose different identifiers, change them in `project.yml`, in `Config/Noctis.storekit`, in `StoreProductID` and in the App Group name everywhere, then run `xcodegen generate` and the tests. Keeping these is far less work.

## 3. App Store Connect

1. Create the app: name, primary language English, bundle ID `com.noctis.app`, SKU of your choice.
2. Agreements, Tax, and Banking must be complete before a subscription can be sold.
3. Create the subscription group **NOCTIS Premium** with the two products in `APP_STORE_LISTING.md` (same identifiers), the one-week free trial on the yearly one, localizations, prices and a review screenshot each.
4. Add the Privacy Policy URL and the Support URL from step 1.
5. App Privacy: enter the answers from `PRIVACY_REPORT.md` section 4 after you have approved it. Age rating: answer the questionnaire. Export compliance: confirm "no non-exempt encryption".
6. Fill in the description, keywords, promotional text, and the reviewer notes from `APP_STORE_LISTING.md`.
7. Create sandbox testers (Users and Access, Sandbox).

## 4. Sign, archive, validate (QA-027)

Pick your team in Xcode (every target) or pass it once on the command line, which applies to every target:

```bash
xcodebuild archive -project Noctis.xcodeproj -scheme Noctis -configuration Release -destination 'generic/platform=iOS' -archivePath build/Noctis.xcarchive DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates
```

Then open the archive in Xcode's Organizer, run **Validate App**, fix what it reports, and **Distribute App**, App Store Connect, Upload. Record the result in `QA_LEDGER.md` (QA-027).
Before this, run `python3 scripts/release_symbol_check.py` on the Release products again if any source changed.

## 5. Real devices (QA-020, QA-129, QA-135, QA-138; `DEVICE_TEST_CHECKLIST.md`)

Run the whole checklist on an iPhone and a paired Apple Watch, with a sandbox account, on the oldest iOS you will support (26.1 if you can) and on the latest. Tick each row with the date and the device.
Nothing in it can be done from the simulator.

## 6. Screenshots

Follow the last section of `APP_STORE_LISTING.md`: 6.9 inch, one clock time, every tab, sample data only, every picture looked at. Add Apple Watch screenshots.

## 7. TestFlight, then submit

1. Install the uploaded build from TestFlight on a device. Run the purchase flow with a sandbox account again, from the TestFlight build, which is the one that will ship.
2. Internal testing for a few days, including an overnight night with the Watch.
3. Add the build to the version, answer the remaining questions, and submit.

## 8. After submission

Every review rejection reason is a row in `QA_LEDGER.md`. If the review team cannot see Health data, point them to the reviewer notes; the app shows its empty states and the labelled Sample night without data.
