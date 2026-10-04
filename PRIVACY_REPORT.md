# PRIVACY_REPORT.md
What NOCTIS does with data, what `App/PrivacyInfo.xcprivacy` says about it, and a draft of the App Store Connect "App Privacy" answers.

Status: **draft for owner review**. It was written from an audit of the code at the commit that adds it, not from a template. It is not legal advice: the owner reviews every sentence, and the published Privacy Policy, this report, the manifest, the App Store Connect answers and the app's own Privacy Center must say the same thing before release. Every claim below that the tests can check is held by `DataInventoryTests` (R41) or `PrivacyManifestTests` (R43); claims that are policy or interpretation, not code, are marked **owner**.

## 1. Short version

- NOCTIS has no server, no account, no sign-in, no analytics service, no advertising and no third-party code (no Swift package outside the repo). It has no iCloud, push or network entitlement. Its one shared storage is an App Group holding a single small file for its widgets (R44); no defaults are shared.
- It reads sleep, heart rate, resting heart rate, heart rate variability and respiratory rate from Apple Health, on the iPhone: when the app is open, and in the background when Apple Health has new sleep data (HealthKit background delivery, R46; iOS decides when). It never writes to Health (`toShare: []`, no write permission asked, `com.apple.developer.healthkit.access` empty). It keeps no copy of the readings, only numbers worked out from them.
- The only network-capable system APIs it imports are StoreKit (Apple's App Store, for Premium) and MessageUI (the Contact support mail composer, which sends only if the person sends the email).
- The only required-reason API its own code calls is `UserDefaults`.
- Nothing is collected by NOCTIS or a partner, and nothing is tracked, as far as the code can show. One optional flow needs an owner decision (section 6, item 1).

## 2. Every data flow

"Leaves" means leaves the iPhone. Rows are the inventory's categories (`DataInventory.shared`); the inventory is the source, this table is a copy.

| Category | Where it lives | Leaves? | Coach sees | In device backup | File protection | How it is deleted |
| --- | --- | --- | --- | --- | --- | --- |
| Apple Health data | Apple Health (NOCTIS keeps no copy) | No: read on the iPhone, read-only | Facts worked out from it (recovery today, last night, usual bedtime and wake, week's average), never raw readings | n/a | Apple-managed | In Apple's Health app |
| Cached summaries | `Application Support/Noctis/home-snapshot.json` | No | No | No | Complete while locked | Data management, Delete |
| Widget summary | `WidgetSnapshot.json` in the App Group container (`group.com.noctis.app`), written by the app, read by the widgets | No: it stays on this iPhone, shared between the app and its widgets only | No | No | Readable after first unlock (set on purpose: a locked iPhone's widgets must read it) | Data management, Delete cached summaries |
| Insights history | `Application Support/Noctis/insights.json` | No | Insights already found, as numbers | No | Complete while locked | Data management, Delete |
| Summaries in memory | Memory only | No | No | n/a | Not on disk | When the app closes, and with Cached summaries |
| Your profile | SwiftData `default.store` (`UserProfileRecord`) | No | Sleep need, wake time, goals; never the name | Yes | Standard | Delete all NOCTIS data |
| Preferences | `UserDefaults`, `noctis.pref.*`, `noctis.winddown.*`, `noctis.breathing.*` | No | No | Yes | Standard | Data management, Reset preferences and goals |
| Sound and meditation choices | `UserDefaults`, `noctis.sounds.*`, `noctis.meditation.*` | No | No | Yes | Standard | Data management, Reset preferences and goals |
| Small app flags | `UserDefaults`, `noctis.*.lastWashDay`, `lastIntroDay`, `noctis.onboarding.*`, `noctis.coach.firstRunSeen` | No | No | Yes | Standard | Delete all NOCTIS data |
| Wake alarm | SwiftData `default.store` (`AlarmConfiguration`) and iOS AlarmKit | No | No | Yes (the store) | Standard | Delete all NOCTIS data (also cancels the alarm) |
| Wind-down history | SwiftData `default.store` (`WindDownSession`) | No | No | Yes | Standard | Data management, Delete |
| Journal | `Application Support/Noctis/Journal/journal.store` | No | No: no sleep, recovery, insights or Coach code can reach it (R35) | No | Complete while locked | Data management, Delete |
| Coach conversations | `Application Support/Noctis/CoachHistory/coach-history.store` | No (Coach answers are made on the iPhone) | n/a | No | Complete while locked | Data management, Delete |
| Scheduled reminders | iOS notification centre (local notifications only) | No | No | n/a | Apple-managed | Delete all NOCTIS data |
| Diagnostic log | The iPhone's unified log (`Logger`, subsystem `com.noctis.app`) | No, unless the person shares a diagnostics report | No | n/a | Apple-managed | iOS clears it |
| Subscription | The App Store (NOCTIS keeps nothing) | Apple's App Store handles purchase, restore and management | No | n/a | Apple-managed | Manage subscription (Apple) |
| Files iOS makes for the app | `Caches/com.noctis.app` (shader cache), iOS saved screen state, the app switcher's picture of the last screen | No | No | No | Apple-managed | iOS; Delete all clears the cache folder |
| Export file | `tmp/NOCTIS-export.json`, only while "Export my data" is in use | Only if the person shares it | No | No | Standard | Removed on leaving Data management and at the next start |

Flows that are the person's own action (`DataInventory.flows`):
- **Contact support**: if the person taps it and sends the email, the mail app sends it to the support address with the app version, build, iOS version and what they wrote. The `mailto:` fallback (no Mail account set up) carries the same body.
- **Export my data** and **Share this night**: a file or picture the person can share; where it goes is up to them.
- **Terms**, **Privacy** (paywall footer), **crisis help** (Coach, findahelpline.com) and **Open Health**: links the person taps. NOCTIS sends nothing with them; the other app or Safari takes over.
- **Subscription** and **device backups**: Apple's own services (section 6, items 3 and 4).

Network-capable APIs found in the code (`DataInventory.networkUses`): `import StoreKit` (StoreManager, EntitlementManager, PaywallScreen, SettingsPages, SettingsScreens, DataManagementViews) and `import MessageUI` (SettingsScreens). No `URLSession`, `URLRequest`, CloudKit, WebKit, Network, AdSupport or tracking API is used anywhere; `DataInventoryNetworkTests` fails if one appears.

## 3. The privacy manifest (`App/PrivacyInfo.xcprivacy`)

| Key | Value | Why |
| --- | --- | --- |
| `NSPrivacyTracking` | `false` | No tracking SDK, no advertising identifier, no data broker, no data combined with another company's. `PrivacyManifestTests` fails if `AdSupport`, `AppTrackingTransparency`, `ASIdentifierManager`, `advertisingIdentifier` or `identifierForVendor` appears, or a remote Swift package is added. |
| `NSPrivacyTrackingDomains` | empty | Nothing tracks, and the app makes no request to any domain. |
| `NSPrivacyCollectedDataTypes` | empty | Nothing leaves the iPhone for NOCTIS or a partner. See section 6, item 1 for the one flow that needs an owner decision. |
| `NSPrivacyAccessedAPITypes` | `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1` | NOCTIS reads and writes its own preferences, goals, sound choices and flags in `UserDefaults` (`AppPreferences`, `SoundPlayer`, `MeditationViewModel`, `HomeViewModel`, `CoachViewModel`, `OnboardingDraftStore`). `CA92.1` is "read and write information that is only accessible to the app itself". There is no App Group, and no extension reads the defaults, so `1C8F.1` does not apply. |

**The widgets' extension** (`NoctisWidgets`, bundle `com.noctis.app.widgets`) has a manifest of its own (`NoctisWidgets/PrivacyInfo.xcprivacy`): tracking off, no collected data, no required-reason API, because the extension and the kit it links use none (it reads one file from the App Group and draws it; `PrivacyManifestTests` scans both). Its entitlements are the App Group alone: no HealthKit, no network, no iCloud. It cannot reach Health, SwiftData or Coach: its only dependency is `NoctisWidgetKit`, which depends on the design tokens.

Required-reason categories audited and **not** used by NOCTIS's own code, so not declared (a category is declared only when used, as Apple asks):
- **File timestamp**: no `creationDate`, `modificationDate`, `contentModificationDate`, `getattrlist`, `stat`, `fstat` or `lstat`. The only file attribute read is a size (`attributesOfItem(...)[.size]` and `.fileSizeKey` in `DataInventory+Size.swift`, for Data management's sizes).
- **System boot time**: no `systemUptime`, `mach_absolute_time` or `mach_continuous_time` in the app's code. (`ContinuousClock` in Coach's answer timing is the Swift standard library's clock, not a listed API.)
- **Disk space**: no `volumeAvailableCapacity*`, `systemFreeSize`, `statfs` or `statvfs`.
- **Active keyboards**: no `activeInputModes`.

How this was checked, beyond reading the code: a scan of every Swift file in the package, the app and the extension (`PrivacyManifestTests.everyRequiredReasonAPIInTheCodeIsDeclaredAndNothingElseIs`), and `nm -u` on the built app and extension binaries, which reference `NSUserDefaults` and none of the other listed symbols. The Alarm extension (`NoctisAlarmWidget`) uses none of the categories and has no manifest. There is no third-party code, so there is no SDK manifest or signature to collect. The manifest is a resource of the app target (checked in the built `NOCTIS.app`).

Info.plist usage strings:
- `NSHealthShareUsageDescription`: "NOCTIS reads your sleep, heart rate, resting heart rate, heart rate variability and respiratory rate from Apple Health to build your sleep plan and show your recovery trends. It never writes to Health." The audit found it left out resting heart rate, which the app reads (`HealthKitProvider`, Recovery); it was added. `PrivacyManifestTests` holds the string to the list of `HealthDataKind` cases. There is no `NSHealthUpdateUsageDescription`, because nothing is written.
- `NSAlarmKitUsageDescription`: "NOCTIS uses an alarm to wake you at the time you set. It can sound and appear on screen even when a Focus is on." Accurate.
- No camera, microphone, location, contacts, photos, tracking or Bluetooth key is present, because none of those APIs is used. `UIBackgroundModes` is `audio`, for sleep sounds the person started.

## 4. Draft answers for App Store Connect, App Privacy (**for owner review**)

These are a draft. The owner decides and submits. The questionnaire's definitions are Apple's, and Apple can change them.

1. **Do you or your third-party partners collect data from this app?** Draft: **No** (data not collected). Depends on section 6, item 1.
2. **Data types**: none selected. In particular, **Health** and **Fitness** are not collected: HealthKit data is read on the device and no copy leaves it. **Purchases** are handled by Apple; NOCTIS has no server and receives no purchase record. **Contact Info, User Content, Identifiers, Usage Data and Diagnostics** are not collected: there is no account, no analytics service and no crash-reporting SDK. (iOS can send crash reports and metrics to developers only for people who opt in to share them with app developers; that is Apple's service, not NOCTIS code.)
3. **Tracking**: Draft: **No**. NOCTIS does not track.
4. **Privacy Policy URL**: required. **Owner** supplies it. The app and the paywall footer currently point at the placeholder `https://noctis.app/privacy`. The policy should say what section 1 says, and that Health data is read and never written.
5. **Health data on the App Store page and in review**: NOCTIS uses HealthKit, so App Review expects the Privacy Policy to say how Health data is used (to build the sleep plan and recovery trends, on the device, never written, never used for advertising or data mining, never shared). Everything in this report supports that; the wording is the owner's.
6. **Account deletion** (App Store Review 5.1.1(v)): NOCTIS has no account, so there is none to delete. Data management says exactly that, and "Delete all NOCTIS data" removes everything the app stores on the iPhone. The line is shown only while `DataInventory.shared.facts.hasAccount` is `false` and no sign-in code exists (`DataInventoryNetworkTests.thereIsNoAccountAndNoSignIn`).

If the owner reads item 1 the other way (section 6, item 1, option B), answer **Yes** and add one data type, **Customer Support**, not used for tracking, with the purpose **App Functionality**, and add the matching `NSPrivacyCollectedDataTypeCustomerSupport` entry to `NSPrivacyCollectedDataTypes` in the manifest (`PrivacyManifestTests` will then need updating on purpose).

## 5. What the app says about privacy, and what backs it

The Privacy Center, Data management, Coach's "How Coach uses your data", Help and onboarding take every privacy sentence from `PrivacyStatements`, which returns one only while the inventory backs it. The four headline statements:

| Statement | Shown only while | Held by |
| --- | --- | --- |
| "NOCTIS reads your sleep and heart data from Apple Health. It never writes to Health." | Health access is read-only | `healthIsOnlyEverRead`, the entitlements and `project.yml` checks |
| "Your data is stored on this iPhone." | Nothing syncs | the `ModelConfiguration(cloudKitDatabase: .none)` check, no iCloud entitlement, no `NSUbiquitousKeyValueStore` |
| "Coach answers are made on your iPhone or built from your data." | Coach uses no remote model | `facts.coachUsesRemoteModel == false`; there is no transport, endpoint or key (`aiRemote` is off, ROADMAP.md) |
| "Nothing is sold or shared." | No category goes to a third party or tracks | no `.thirdParty` destination, the tracking scan above |

## 6. Ambiguities and decisions for the owner

1. **The support email (the one open flow).** Contact support opens the system mail composer (or a `mailto:` link) addressed to the support inbox, with the app version, build number and iOS version in the body. The person must press Send; nothing is sent by the app on its own, and NOCTIS has no server that receives it. Whether Apple's questionnaire counts an email the person chooses to send as data "collected" (Customer Support, and the sender's email address) is an interpretation. Option A (draft above): not collected, because the app transmits nothing and the person's mail app sends the message. Option B: declare Customer Support. This report does not decide it. **Owner.**
2. **Health: onboarding asks for three kinds, the app reads five.** Onboarding asks Apple Health for sleep, heart rate and HRV (`HealthScreen.requestedKinds`); "Connect Apple Health" elsewhere asks for all five (`HealthDataKind.allCases`). `HealthKitProvider.authorizationStatus()` asks HealthKit about all five kinds, and Home, Sleep, Recovery and Insights only load data when it says `.authorized`. From the code, after onboarding alone (resting heart rate and respiratory rate never asked) HealthKit's `statusForAuthorizationRequest` should report that a request is still needed, so those screens may show "Connect Apple Health" until the person connects again, and the person may see Apple's Health sheet twice. **Not run against real HealthKit** (the simulator uses the mock provider), so this is a code reading, not a confirmed bug. The usage string now names all five; the onboarding screen lists three. Not changed here. **Owner**: confirm on a real iPhone, then either ask for all five in onboarding or have the status check use only the kinds that were asked.
3. **Device backups.** The default SwiftData store (profile, wake alarm, wind-down history) and the preferences, sound choices and flags are in iCloud and computer backups, with iOS's standard file protection (readable after first unlock). The Journal, Coach conversations, insights and cached summaries are excluded from backups and use complete protection. The headline "Your data is stored on this iPhone." is true of where NOCTIS keeps it; a backup is Apple's copy of the iPhone, not NOCTIS syncing. The inventory says so in "What may leave", but the owner decides whether the headline should say "backups aside", whether the profile's optional name should be excluded from backups, and whether the default store should move to complete protection. **Owner.**
4. **Subscription.** Purchases go through StoreKit and Apple's App Store. There is no receipt validation server, so the developer receives nothing from the app. If a server or an analytics event for purchases is ever added, Purchases must be declared and the manifest changed.
5. **"Deleted" and free pages.** Deleting one kind of data (for example Coach history) removes its rows; the SQLite file is not vacuumed, so the bytes of deleted text can stay in the file's free pages until they are overwritten (the Coach store stayed near 111 KB after its rows were deleted in testing). "Delete all NOCTIS data" removes the store files themselves. The page says "deleted". **Owner**: accept, reword ("removed from NOCTIS"), or add a vacuum after a single-category delete.
6. **The app switcher's picture.** iOS keeps a small picture of the app's last screen for the app switcher. It can show a recovery score or a Journal entry. NOCTIS does not hide its screens when the app goes to the background. The inventory says so under "Files iOS makes for the app". **Owner**: whether to blur the content when the app becomes inactive.
7. **The diagnostic log.** `NoctisAnalytics` writes events (`paywall_viewed`, `plan_selected`, `trial_started`, `purchase_completed`, `paywall_dismissed`, `onboarding_completed`) with the plan's product id to Apple's unified log, marked `privacy: .public`, so they are readable by anyone who holds the unlocked iPhone and collects a diagnostics report. They hold no Health value, name or written text (parameters are plan ids and flags only). They never leave the iPhone by themselves. **Owner**: whether "Diagnostic log" should be listed in the policy.
8. **The Journal and "Export my data".** R35 said no code outside the Journal's own target may read an entry. The export is the one other reader: it asks the Journal's own `JournalExport` for the person's entries when the person asks for a copy. R35 was amended (R41), the dependency checks of `JournalPrivacyTests` still hold, and the export file is written to a temporary folder, shared only if the person shares it, and removed afterwards. **Owner**: review that the export containing the Journal's text is what you intend.
9. **Placeholders the owner supplies.** Terms URL, Privacy Policy URL (`StoreLegalLinks`) and the support address are placeholders (`https://noctis.app/terms`, `https://noctis.app/privacy`, `support@noctis.app`; ROADMAP.md). App Store Connect requires a real Privacy Policy URL. The Privacy Center's wording ("What NOCTIS reads", "Why", "What you can delete") is generated from the inventory; the policy must not contradict it.
10. **Alarm.** The wake alarm is scheduled with AlarmKit, which iOS holds, so it can ring when NOCTIS is closed. "Delete all NOCTIS data" cancels it first (`AlarmService.disable()`); on a real iPhone, confirm after a delete-all that the alarm is gone (it cannot be checked in the simulator).
11. **Reading Health in the background (R46).** NOCTIS now asks Apple Health to wake it when new sleep, HRV or resting heart rate data arrives, and refreshes the widgets' summary then. The reading is still on the iPhone and nothing new is stored or sent; the Privacy Center, Help and the Health usage string say it ("...and in the background when Apple Health has new sleep data (iOS decides when)"). **Owner**: whether the Privacy Policy should say the same, and whether "keep your widgets up to date" is the wording you want in the system's Health permission sheet.
12. **Not covered here.** Export compliance (`ITSAppUsesNonExemptEncryption`), the age rating, accessibility labels and the medical-device wording ("NOCTIS isn't a medical device and doesn't diagnose or treat any condition.") are outside this report.

## 7. How this stays true

- `DataInventoryTests` (R41) holds the inventory to the code: every `@Model` class, every `"noctis.…"` key, every file, every network-capable API.
- `PrivacyManifestTests` (R43) holds the manifest to the code: tracking and collected-data entries against the inventory and the scans, every required-reason API category against the code, the reason code against the App Group and extension facts, the Health usage string against `HealthDataKind`, and this report's existence and coverage of every inventory category.
- Adding a store, a key, a network call, a package or a required-reason API makes a test fail until the inventory, the manifest and this report are changed on purpose.
