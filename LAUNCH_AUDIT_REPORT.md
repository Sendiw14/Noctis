# LAUNCH_AUDIT_REPORT.md

NOCTIS 1.0 (1), audited 2026-11-03 against `NOCTIS_LAUNCH_AUDIT.md`. **Nothing was fixed.** No app code, config or git history was changed by this audit; it added this file and `AUDIT_PROGRESS.md`. Fixes wait for owner approval.

## Verdict: NO-GO

The code is in good shape. The blockers are mostly outside the code. Exact list:

| ID | Blocker | Owner of the fix |
| --- | --- | --- |
| N-01 | Terms, Privacy and support address point at a domain that is for sale | Owner, then a 3-line code change |
| N-02 | No signing team, bundle IDs or App Group registered; no signed archive; Validate App never run | Owner |
| N-03 | Subscriptions not created in App Store Connect; without them the paywall shows only "We couldn't load plans" | Owner |
| N-04 | A reviewer sees an empty app on every tab, and the review notes don't solve it | Owner (video) or code (demo mode) |
| N-05 | Never run on a real iPhone, a real Apple Watch, iOS 26.1, or with a real purchase | Owner |

Ten HIGH items should go before submission too (N-06 to N-12 and N-27 to N-29, section 3). The owner confirmed a **worldwide** release on 2026-11-03; N-27 to N-34 come from that.

### Read this first: the tree moved during the audit

- **Another Claude session is working in this same checkout.** It edited `Packages/NoctisKit/Tests/NoctisKitTests/PreferencesTests.swift` at 17:52 and touched `NotificationCoordinator.swift` at 17:53, after the baseline finished. It ran `pkill -f xcodebuild`, which **killed this audit's UI test and Thread Sanitizer run** (exit 144). That session was left alone.
- Baseline numbers below describe the tree as it stood from about 17:28 to 17:48. Re-run them once the other session stops.
- **Stage 1B is uncommitted, and there is no git remote** (N-06). 74 paths exist only on this Mac.

Evidence labels: **[V]** verified by running it or reading the code here. **[D]** read from an earlier project document, not re-run. **[U]** UNVERIFIED, on the human checklist.

## 1. App summary (Phase 0)

NOCTIS is a local-only sleep and recovery app for iPhone with an Apple Watch companion. It reads Apple Health, works out last night's sleep, a recovery score and tonight's bedtime on the device, and offers a wake alarm (AlarmKit), wind-down, breathing, meditation, synthesized sleep sounds, a journal, insights, weekly and monthly reviews, and a Coach that answers from the person's own numbers using Apple's on-device model or fixed templates. It has widgets, controls, a Live Activity, Siri intents and Watch complications. It has no server, no third-party code and no analytics service. It is free with one auto-renewing subscription group (yearly with a one-week trial, monthly).

| Item | Finding |
| --- | --- |
| Targets | `Noctis` (iOS), `NoctisWidgets`, `NoctisAlarmWidget`, `NOCTISWatch`, `NOCTISWatchWidgets`, `NoctisStoreTests`, `NoctisUITests` |
| Project source | `project.yml` (XcodeGen). A regeneration in a copy produced an identical `project.pbxproj` [V] |
| Configs and schemes | Debug, Release. Shared: `Noctis`, `NOCTIS-Unit`, `NOCTIS-Store` |
| Toolchain | Xcode 27.0, Swift 6.4, SDK iOS and watchOS 27.0. Meets the current upload rule (Xcode 26 or later) [V] |
| Deployment | iOS 26.1, watchOS 26.0. iPhone only, portrait |
| Bundle IDs | `com.noctis.app`, `.widgets`, `.alarm`, `.watchkitapp`, `.watchkitapp.widgets`. All 1.0 (1) in the built bundle [V] |
| Entitlements | HealthKit (read, background delivery), Sign in with Apple, App Group `group.com.noctis.app` |
| Permissions | Health (read), Notifications, AlarmKit |
| Background modes | iOS `audio`; Watch `mindfulness` |
| Packages | One local package, `NoctisKit`, with 29 source modules. No third-party dependency |
| Network | Apple only: StoreKit, Sign in with Apple, WatchConnectivity. No `URLSession`, `WKWebView` or CloudKit in shipped code [V] |
| Screens | Onboarding (Welcome, Goal, Rhythm, Sample night, Health, Notifications, Plan, Paywall). Tabs: Home, Sleep, Recovery, Insights, Coach. Also Tonight, Sounds, Wind-down, Breathing, Meditation, Reflect, Reviews, Profile, Settings, Privacy Center, Data management. Watch: five pages plus breathing |

### Baseline (the "before" column)

| Check | Result |
| --- | --- |
| iOS Debug, simulator | Built, 0 warnings [V] |
| iOS Release, device, unsigned | Built, 0 warnings [V] |
| Watch Debug and Release | Built, 0 warnings [V] |
| Package unit tests | 2,767 tests in 380 suites: 2,766 passed, 0 failed, 1 skipped (`renderLoadedPlanCards`, a screenshot helper) [V] |
| `NOCTIS-Store` purchase tests | 24 tests, 0 failed, 1 known issue (StoreKitTest reports a declined Ask to Buy as entitled) [V] |
| UI tests | **Not run.** 227 test functions exist. The chosen subset was killed during its build (see above) |
| Thread Sanitizer | **Not run**, same reason |
| Line coverage | 38.2% across all sources, 49.5% with tests included [V] |
| Coverage of core logic | SleepKit 92.4, RecoveryKit 97.9, SleepAnalysisKit 98.8, InsightsKit 97.7, PremiumKit 98.4, ReviewKit 97.2, NoctisCore 90.4, CoachKit 92.4, NightKit 89.7. Meets the 80% target. HealthProviding is 70.2 because the real HealthKit provider can't run in tests [V] |
| Code size | Shipped Swift 76,900 lines in 416 files. Tests about 47,340 lines in 182 files |
| Compiler warnings in tests | 1 (`PremiumExpiryTests.swift:408`) |
| SwiftLint, default rules | 4,173 violations (394 errors), 3,411 of them `line_length`. No `.swiftlint.yml` exists [V] |
| swift-format, project config | 14 findings [V] |
| Force operations | SwiftLint flags 5, all on constants: `CoachTokens.swift:7`, `NoctisStore.swift:42`, `WidgetLink.swift:20,59`, `WatchComplications.swift:26`. Also `StoreConstants.swift:18-19`, which it didn't flag [V] |
| `TODO`, `FIXME`, `print`, empty `catch`, `UIPasteboard` | 0 in shipped code [V] |
| gitleaks, history and tree | 4 hits, all false positives on `NOCTIS_EXPECT_HOUR12` in `Config/NOCTIS.xctestplan` [V] |
| `release_symbol_check.py` | 7 binaries, 0 DEBUG hits [V] |
| Tools missing | Periphery, trufflehog, fastlane. Nothing was installed |

## 2. NOCTIS-specific checks

| Check | Result |
| --- | --- |
| Medical wording in copy | Clean of diagnosis and treatment claims. Only uses are disclaimers and the Coach redirect [V]. Outcome-style marketing remains: N-07, N-18 |
| "Not a medical device" | Welcome, paywall, About, Coach, Watch and description [V] |
| Score explanations | "How this is calculated" on Recovery and Home, plus Help articles [V] |
| Harmful advice | No caffeine, supplement or similar guidance. Sleep need is limited to 5 to 10 hours (`ProfileEditors.swift:171`) [V] |
| HealthKit purpose string | Present, but it doesn't match what is asked: N-08 |
| Types requested | Respiratory rate is read and not used: N-08. Resting heart rate is used and not asked for: N-09 |
| Denied or partial access | Never claims "connected"; empty states with Open Health and Health data settings [V] |
| Health data to third parties | No third party exists; manifests declare no tracking and no collection [V]. Analytics and Coach log lines carry event names and plan ids only. Other log call sites were not all read line by line |
| iCloud | `cloudKitDatabase: .none` on all stores; no CloudKit entitlement [V] |
| Data Protection | Journal, Coach, insights, reviews, Home snapshot use `.complete`. Widget and Watch files use until-first-unlock, which widgets need. `default.store` sets no class and is in backups: N-21 |
| Background delivery | Entitlement present, observers set up when the container is created at launch [V]. Real wake-ups are [U] |
| Sleep edge cases | Tests mention DST (95 files), time zones (52), naps (75), midnight (35), duplicates (6), manual entries (7). A keyword count, not a review of each case |
| Reviewer without data | **Fails:** N-04 |
| Watch | Companion only (no `WKRunsIndependentlyOfCompanionApp`), reads no Health data, has states for no snapshot and an unreachable iPhone [V]. Overnight battery, delivery and Always-On are [U] |
| Alarm | AlarmKit [V]. `SilentMeditationAudio` is a test stand-in that plays nothing, not a keep-alive hack [V] |
| Sounds | `audio` mode with `.playback`, interruption handling and lock screen controls [V]. Real behavior is [U] |
| Time-sensitive notifications | None used [V] |
| Free tier | Works without paying; the paywall has a visible Close and "Continue with the free plan" [V] |
| Paywall promise | **Fails:** N-07 |
| Privacy policy | Covers HealthKit, storage and deletion. Missing explicit wording: N-10 |
| Account deletion | Present. Token revocation isn't possible as built: N-11 |

## 3. Findings

| ID | Severity | Area | Finding | file:line | Fix |
| --- | --- | --- | --- | --- | --- |
| N-01 | BLOCKER | Legal | Terms and Privacy return 404, and `noctis.app` redirects to a domain-sale page (tested today). The support address is on that same unowned domain. The paywall and Settings link to them. Guidelines 2.1(a), 3.1.2 | `NoctisCore/Store/StoreConstants.swift:18-24` | Host `Docs/site/`, fill the `[[...]]` placeholders, change the constants, run `SettingsTests` and `StoreTests` |
| N-02 | BLOCKER | Release | No `DEVELOPMENT_TEAM`, no registered IDs, no signed archive, no Validate App [V for the project; U for the account] | `project.yml` | Owner registers IDs and sets the team; archive and validate |
| N-03 | BLOCKER | IAP | Without products in App Store Connect the paywall shows "We couldn't load plans", seen today in a Release build with no StoreKit config. A reviewer would see no way to buy | `Config/Noctis.storekit` | Create both products, attach them to version 1.0 with review screenshots |
| N-04 | BLOCKER | Review 2.1 | Release has no demo mode. With Health allowed and no samples, Home, Recovery and Coach showed "No sleep data yet" or "needs a few nights" (Release build, simulator; Sleep and Insights tabs not opened). Coach's input is disabled. The notes ask the reviewer to add sleep samples, but a baseline needs 5 nights and HRV needs a Watch | `Docs/store/APP_STORE_LISTING.md:92`, `RecoveryKit/BaselineEngine.swift:61` | Recommended: record a real-device video and link it in the notes (no code). Alternative: a labeled sample mode in Release, which is new shipped code and needs its own tests |
| N-05 | BLOCKER | QA | No real iPhone, real Watch, iOS 26.x or real purchase run. Only iOS 27 and watchOS 27 simulators are installed | `Docs/DEVICE_TEST_CHECKLIST.md` | Run the checklist; install a 26.x runtime |
| N-06 | HIGH | Repo safety | 74 paths uncommitted, no git remote, Stage 1B in no backup, a second session editing the same tree | repo | Stop concurrent work, commit Stage 1B, add a private remote |
| N-07 | HIGH | Review 1.4.1, 2.3 | Paywall headline **"Sleep deeper."** promises a health outcome. Nothing in the app measures or causes deeper sleep | `OnboardingFeature/PaywallScreen.swift:678-682`, `PaywallFacts.swift:141` | Say what it does, e.g. "Know your nights." Owner picks the words |
| N-08 | HIGH | Review 5.1.1(iii) | **Respiratory rate is requested but no score, insight or review uses it.** It is only fetched for its last-sample date in Settings. The purpose string, policy and "Add context to unusual nights." all imply a use. Separately, the first Health sheet shows 3 topics while its explanation names 5 (seen today) | `HealthProviding/HealthModels.swift:117`, `HealthKitProvider.swift:151`, `NoctisCore/HealthDataStatus.swift:82`, `project.yml:114`, `Docs/site/privacy.html` | Remove the kind and update the string, policy, inventory, Privacy Center and tests. Name only what is read |
| N-09 | HIGH | Function | **Resting heart rate is a scored Recovery factor, but onboarding doesn't request it.** Most people never see Settings, so their score runs without that factor and never reaches the two-signal cap, while the description says it uses it. By code; the score difference wasn't measured | `HealthModels.swift:136`, `HealthDataProviding.swift:40`, `RecoveryRepository.swift:92`, `RecoveryKit/RecoveryEngine.swift:242` | Add `.restingHeartRate` to `core`. This changes an existing rule (R69), so the owner approves it |
| N-10 | HIGH | Privacy | Policy never says data is **never sold** or never used for marketing, and states no retention. `[[...]]` placeholders remain | `Docs/site/privacy.html:13,34,48` | Add both sentences and fill the placeholders |
| N-11 | HIGH | Review 5.1.1(v) | Sign in with Apple is on the first screen but does nothing. No token or server exists, so the REST revocation Apple's deletion page asks for can't be done. It adds a review question for no feature | `OnboardingFeature/WelcomeScreen.swift:79`, `ProfileFeature/ProfileScreen.swift:225`, `NoctisCore/Account/AccountStore.swift` | Recommended: remove it from 1.0. This is a user-visible change, so the owner decides |
| N-12 | HIGH | Metadata | Listing says 6.9-inch screenshots are required. Apple's page now lists iPhone medium display (1206 x 2622 or 1179 x 2556). No usable set exists, and no Watch set | `Docs/store/APP_STORE_LISTING.md:145` | Capture on iPhone 17 and Series 12 (section 6). Recheck the page in App Store Connect |
| N-13 | MEDIUM | HealthKit | iOS 27's Health sheet adds "Past 30 Days and Future Data" (seen today). Apps can't see the choice, so 90-day Recovery and old reviews may silently lack data. No test covers it | Health sheet | Test that choice; add a line to the empty state if it reads as broken |
| N-14 | MEDIUM | UI | With Button Shapes on, paywall footer links overlap, and at AX5 "Privacy" is hidden [D, R-21] | `PaywallScreen.swift:452-454` | Lay out without negative padding |
| N-15 | MEDIUM | Accessibility | Tier C settings and VoiceOver traversal unverified on the final build [D, R-14]. Accessibility Nutrition Labels can't be answered honestly yet | `Docs/ACCESSIBILITY_TEST_MATRIX.md` | Run the matrix |
| N-16 | MEDIUM | Decisions | Open owner decisions: 48-hour renewal slack (R-07), payment-problem wording, backup wording, Family Sharing [D] | Stage 1B report 8.4 | Decide before release |
| N-17 | MEDIUM | Tooling | No CI, `.swiftlint.yml`, `ARCHITECTURE.md`, `CHANGELOG.md` or xcconfig files | repo | Add after approval |
| N-18 | MEDIUM | Review 1.4.1 | Softer outcome wording: "Better nights. A brighter you.", and goal cards "Faster recovery / Bounce back", "More energy / Sharper all day", "Clearer focus" | `OnboardingFeature/WelcomeBands.swift:22-25`, `GoalScreen.swift:16-22` | Goals are the person's aim, not a promise, so lower risk. Owner reviews the wording |
| N-19 | MEDIUM | Metadata | Keywords repeat `sleep` and `recovery` from the name, wasting 15 characters; subtitle repeats them too | `APP_STORE_LISTING.md:30` | Use section 6 |
| N-20 | MEDIUM | Architecture | `CoachKit` (an engine) depends on `HomeFeature`; Sleep, Recovery, Insights, Night and Profile features depend on `HomeFeature`. Two onboarding views call `UNUserNotificationCenter` directly | `Package.swift`, `NotificationsScreen.swift:168`, `PaywallScreen.swift:571` | v1.1 for the module split; the two calls are PRE-LAUNCH |
| N-21 | LOW | Storage | `default.store` (profile, alarm, wind-down) sets no protection class and is in backups. Already disclosed as an owner decision [D] | `NoctisCore/NoctisStore.swift:16` | Confirm the class on a device, or set one |
| N-22 | LOW | Config | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` on the Watch has no effect: the built Watch plist lacks the key. The listing claims both targets have it | `project.yml:225` | Add it to `Watch/App/Info.plist` properties or correct the doc |
| N-23 | LOW | Docs | Comment says no Security symbol is linked, but the app links `Security.framework` for the Keychain. No export impact | `project.yml:105` | Fix the comment |
| N-24 | LOW | Copy | Skipping goals still shows "Focus: Better sleep" as if chosen. "Model recovery-v3" shows in the calculation card | `OnboardingFeature/PlanScreen.swift:200`, `RecoveryFeature/RecoveryTodayViews.swift:432` | Hide both |
| N-25 | LOW | Quality | 15 `#Preview` for 464 view structs; 100 `.font(.system(size:` uses; 45 files over the default length rule; text in Swift rather than catalogs | package | v1.1 |
| N-26 | LOW | Repo | 10 older audit and report files plus 2 patches at the repo root | repo | Move to `Docs/audits/` |
| N-27 | HIGH | Safety, worldwide | **A crisis message in another language can miss the crisis reply.** The crisis patterns are English only. A miss goes to the on-device classifier, and where that is unavailable (no Apple Intelligence, unsupported language, timeout) the person gets "I can help with questions about your sleep and recovery." Coach accepts any language | `CoachKit/CoachQuestionRouter.swift:100`, `CoachKit/AIService.swift:163-171,217`, `CoachKit/Resources/Coach.xcstrings` | Recommended: show a permanent "Need urgent help?" link to the helpline screen on the unknown reply, in every language. Translated patterns can follow, reviewed by a qualified person |
| N-28 | HIGH | Territories | **China mainland can't be included as things stand.** Apple says some apps need a valid ICP Filing Number, and shows "ICP Filing Number Missing" with the app unavailable there. Apple Intelligence availability there is also [U] | App Store Connect, App Information | **Decided by the owner 2026-11-03: exclude China mainland for now.** Deselect it under Pricing and Availability. Revisit later with a local adviser |
| N-29 | HIGH | Legal, age | Texas, Utah and Louisiana have app-store age laws, and Apple says developers are responsible for their own age restrictions where legally required. Apple's page doesn't say what a no-API app must do. NOCTIS doesn't use the Declared Age Range API, and has no server to receive `RESCIND_CONSENT` notifications [U] | none in code | Get a legal answer before selling in those states. Don't add the API until you have it |
| N-30 | MEDIUM | Language | English only, in every storefront. Allowed by Apple, but limits conversion, and the listing will be English everywhere. Only part of the text is in catalogs (681 keys in `needs-translation.csv`); much is in Swift, so translation isn't ready | `Localizations/needs-translation.csv` | Launch in English and say so in the listing. Plan the first languages from sales data, v1.1 |
| N-31 | MEDIUM | Safety, worldwide | Helplines cover 8 countries (LK, US, CA, GB, IE, AU, NZ, IN). Everyone else gets "Your local emergency number: 112", which is not every country's number, plus the findahelpline.com directory | `CoachKit/CoachHelplines.swift:45-51` | Say "your local emergency number" with no number outside listed regions, keep the directory link prominent, and check each listed number on a schedule |
| N-32 | MEDIUM | Locale QA | The locale test plan covers four English regions only (LK, US, NZ, AU). Today's launches with `th_TH` and `ar_SA` Umm al-Qura didn't crash; Home showed correct 24-hour time and the local calendar date. That covers the empty Home only. Engines use a fixed Gregorian calendar by design. Week and month screens with data under non-Gregorian calendars are untested | `Config/NOCTIS.xctestplan` | Add a Saudi, a Thai and a Japanese configuration; check a Premium paywall in JPY, where the price has no decimals |
| N-33 | MEDIUM | Legal, worldwide | Local-only storage doesn't by itself remove GDPR duties, and health data is a special category. EU MDR turns on intended purpose. Other laws to raise with counsel: UK GDPR, an EU and UK representative, CCPA, and US state health-data laws such as Washington's My Health My Data Act (from memory, not checked for this report) [U] | `Docs/site/privacy.html` | One review by a lawyer, covering controller status, support email, and the "recovery" and "readiness" wording |
| N-34 | LOW | Privacy | Policy states no minimum age and doesn't address people under 13 or 16 | `Docs/site/privacy.html` | Add a sentence once N-29 is answered |

Checked and fine [V unless marked]: no tracking, ads, or SDKs; no ATS exceptions; no hardcoded IPv4; deep links limited to a fixed list that only opens screens (`WidgetURLRouter.swift`); `Transaction.updates` finishes verified transactions; Restore on the paywall and in Settings; delete-account warns the subscription continues; app icons 1024 with no alpha; launch screen set; 5 privacy manifests; no required-reason symbols in the release binaries beyond UserDefaults (`CA92.1` declared; no shared-suite defaults in shipped code); app-switcher privacy shield.

## 4. Phase status

| Phase | Status |
| --- | --- |
| 1 Build and config | Pass except N-02, N-22. Validate App [U] |
| 2 Privacy and legal | N-01, N-08, N-10. Local-law review [U] |
| 3 Auth | No accounts. N-11. No demo account is needed |
| 4 IAP | Code passes [V]; N-03. Sandbox and TestFlight [U]. No server validation, which fits a no-server app |
| 5 Functional QA | Fresh install walked in Release up to Home, then Recovery and Coach [V]. Other tabs, device matrix, migration [D or U] |
| 6 Extensions | Built with matching versions [V]. Behavior on devices [U] |
| 7 Stability | Sanitizers not run; Instruments not run [U]. No crash SDK by design; rely on Xcode Organizer and keep dSYMs |
| 8 Security | Clean scans [V]. Proxy inspection [U]. No backend |
| 9 Backend | Not applicable. No kill switch or force-update; hotfix means expedited review |
| 10 Notifications | Asked in context, skippable; cold-start routing [D] |
| 11 UI and HIG | N-07, N-14, N-18, N-24. English only, no third-party fonts or sounds [V] |
| 12 Accessibility | N-15 |
| 13 Review risks | Section 5 |
| 14 Metadata | Section 6 |
| 15 Release plan | `SUBMIT_CHECKLIST.md` exists. Recommend manual release with phased rollout |
| 16 Commonly missed | No CloudKit, universal links or UGC, so those are not applicable. Reinstall covered by `FreshInstallGuard` [V, code]. Rest in the checklist |
| 17 Architecture | Section 8 |
| 18 Cleanup | Earlier pass `Docs/CLEANUP_REPORT.md` [D]. Periphery not run: installing needs your OK |
| 19 Code quality | Baseline above; scorecard in section 9 |
| 20 MASVS | Section 10 |

## 5. App Review risks

| Guideline | Trigger | Fix or explanation |
| --- | --- | --- |
| 1.4.1 | "Sleep deeper.", score explanations | N-07. Methodology is already disclosed in the app |
| 2.1 | Empty app, dead URLs, plans not loading | N-01, N-03, N-04 |
| 2.3 | Listing claims resting heart rate use by default | N-09 |
| 2.5.4 | `audio` background mode | Sound and meditation audio only; say so in the notes |
| 3.1.2 | Paywall terms | Price, trial and renewal lines exist in code. Links are dead (N-01). The loaded state wasn't seen in this run |
| 4.2 | Thin without data | Free tier is real; the video covers it |
| 4.3 | Crowded sleep category | Unique design; no action |
| 4.8 | Only Apple sign-in, optional | Not triggered |
| 5.1.1 | Respiratory rate, Sign in with Apple deletion | N-08, N-11 |
| 5.1.2 | Coach and AI | On-device Apple model only; no third-party AI. Already in the notes |
| 5.1.3 | Health data | No iCloud, ads or sharing [V]; N-10 |

## 6. Ready-to-paste drafts

Each of these needs your review. Marketing text is a claim.

**App Privacy.** Data collected: **No**. Tracking: **No**. Health and Fitness: not collected, because nothing leaves the device. Support email: recommended reading is that it falls under Apple's optional disclosure (a customer service request, unrelated to the primary purpose, sent by the person each time). This is a judgment call on one criterion, since the sender name shows in the system Mail composer rather than the app. If you'd rather not rely on it, declare Customer Support, not linked for tracking, purpose App Functionality, and update the manifest.

**Age rating.** Parental Controls, Age Assurance, Unrestricted Web Access, User-Generated Content, Social Media, Messaging, Advertising: No. Mature Themes, Sexuality, Violence, Chance-Based: None. Medical or Treatment Information: None. **Health or Wellness Topics: Yes.** Per Apple's table this should give **9+**. App Store Connect has the final word, and the end of Apple's page wasn't read.

**Export compliance.** Uses only exempt system encryption. `ITSAppUsesNonExemptEncryption = NO` is in the iOS app's built plist [V].

**Name:** NOCTIS: Sleep & Recovery (24). **Subtitle:** Your bedtime plan, on device (28).

**Keywords (99):** `hrv,bedtime,alarm,wind,down,breathing,sounds,meditation,widget,heart,rate,routine,readiness,journal`

**Promotional text:** keep the draft in `APP_STORE_LISTING.md`. **Description:** keep the draft, after N-08 and N-09 are settled. **What's New:** First release.

**Categories:** Health & Fitness, then Lifestyle. **Release:** manual, phased. **URLs:** your published support and privacy pages.

**Territories:** all except China mainland (owner's decision, N-28). Texas, Utah and Louisiana can't be excluded on their own through a storefront, so N-29 needs its answer before US release. **Language:** English; add "English only" to the description.

**Screenshot plan.** iPhone 1206 x 2622 from the iPhone 17 simulator at 9:41: Home, Sleep, Recovery with its calculation card, Insights, Coach, Tonight, paywall. Apple Watch 416 x 496 from Series 12 (46mm): recovery page, a complication, breathing. Use sample data the app can really show.

**Review notes** (assume N-08, N-09 and N-11 are approved; change them if not):

> NOCTIS reads sleep, heart rate, resting heart rate and heart rate variability from Apple Health, read only. It has no server and no account; Sign-in is not required.
>
> Scores need real nights: a baseline takes 5 nights, and HRV comes from an Apple Watch. A review device will show empty states, which are expected. Video of the app with real data: [VIDEO LINK].
>
> Apple Watch is optional. An iPhone alone records no sleep, but any app that writes sleep to Health works.
>
> Premium: tap a locked item or open Settings, then Subscription, and buy with your sandbox account. Restore is on the paywall and in Settings.
>
> Permissions: Health, Notifications, AlarmKit for the wake alarm. The audio background mode is for sleep sounds and meditation the person starts.
>
> Coach uses Apple's on-device model where available and fixed templates otherwise. No data goes to any third party. Medical and crisis questions get fixed replies.
>
> NOCTIS isn't a medical device and doesn't diagnose or treat any condition.

## 7. HUMAN CHECKLIST

- [ ] Stop the second session or agree who owns the checkout; commit Stage 1B; add a private remote
- [ ] Buy or choose a domain; publish privacy, terms and support; create a working inbox
- [ ] Paid Apps agreement, tax, banking; EU DSA trader status; D-U-N-S if an organization
- [ ] 2FA on the developer account; team roles; Small Business Program enrollment
- [ ] Check the name in App Store Connect; trademark search. A web search found no app named exactly "Noctis", but found Nocty, Noctelle, Noctura, Noctune and SomnusShardNoctis nearby. Not a legal opinion
- [ ] Confirm `com.noctis.app` can be registered; you don't own `noctis.app`
- [ ] Create subscriptions; set prices, tax category, Family Sharing, offers; add review screenshots
- [ ] Sign, archive, Validate App; keep the `.xcarchive` and dSYMs; tag the commit
- [ ] Device pass: real iPhone, real Watch, iOS 26.1, sandbox purchase, Ask to Buy, expiry, refund, Watch installed and not, phone away, overnight battery, alarm in Focus, sound lock-screen controls, background delivery
- [ ] iPad compatibility mode: reviewers may run an iPhone app on iPad
- [ ] Inspect Release traffic with a proxy
- [ ] Instruments, plus Address and Thread Sanitizers
- [ ] Record the review video and capture screenshots
- [ ] Accessibility Nutrition Label answers
- [ ] Legal review: GDPR, CCPA. Sri Lanka's PDPA: sources report key provisions start 1 January 2027 but disagree on which; check the Gazette
- [ ] TestFlight internal and external round; support FAQ
- [ ] Worldwide: deselect China mainland in App Store Connect, Pricing and Availability (N-28)
- [ ] Worldwide: legal answer on US state age laws (N-29), and the review in N-33
- [ ] Worldwide: check the price per storefront and App Store tax category; EU trader status publishes your address and phone
- [ ] Worldwide: review the age rating result per region; Australia and Brazil use their own values
- [ ] Worldwide: support plan for time zones and non-English email

## 8. Architecture (Phase 17), for your approval

Already close to the target: pure engines, HealthKit only in `HealthProviding`, DI through `AppContainer`, shared code in one package used by iOS, Watch and widgets.

**Recommendation: do not restructure before launch.** `NoctisKit` splits into 29 modules, finer than the four target packages, and a test holds some of those boundaries. Merging them is not mechanical, and many source-text tests read files by path.

```
Current                          Proposed now (PRE-LAUNCH)        Target, v1.1
App/                             App/                             Apps/iOS/
Watch/{App,Widgets}              unchanged                        Apps/Watch/
Widgets/{Home,Alarm}             unchanged                        Apps/Widgets/
Packages/NoctisKit/ (29 modules) unchanged                        Group into Core, Data, Purchases, DesignSystem
Config/                          add .xcconfig only if needed     Config/
Tests/{StoreTests,UITests}       unchanged                        Tests/
10 reports, 2 patches at root    Docs/audits/                     Docs/audits/
scripts/                         unchanged                        Scripts/
```

`ARCHITECTURE.md` with the Mermaid diagram comes after approval, with the other documents.

## 9. Code quality scorecard

| Metric | Before | After |
| --- | --- | --- |
| Compiler warnings, shipped targets | 0 | pending |
| Compiler warnings, tests | 1 | pending |
| SwiftLint (default rules, no config) | 4,173 | pending |
| swift-format | 14 | pending |
| Coverage, all sources | 38.2% | pending |
| Files over the default length rule | 45 | pending |
| Force operations | 7, all on constants | pending |
| Third-party dependencies | 0 | pending |

## 10. Security, mapped to OWASP MASVS

| Category | Result |
| --- | --- |
| STORAGE | Good file protection; N-21. Keychain uses `AfterFirstUnlockThisDeviceOnly` |
| CRYPTO | None of its own |
| AUTH | No accounts; N-11 |
| NETWORK | No own traffic in code; `strings` shows only Apple, helpline and the dead legal URLs. Proxy check [U] |
| PLATFORM | URL scheme limited to a fixed list and starts nothing; no pasteboard use |
| CODE | No third-party code; gitleaks clean of real secrets; DEBUG code absent from Release |
| RESILIENCE | No jailbreak or tamper checks; entitlement trusts StoreKit verification. Reasonable for this app |
| PRIVACY | No tracking; N-08, N-10 |

## Next, after approval

Your order: cleanup (18), PRE-LAUNCH architecture (17), code quality (19), BLOCKER and HIGH fixes, then re-run everything. Suggested change: commit Stage 1B first (N-06), or there's no clean baseline to diff against. Final GO needs the real-device pass.

## Sources

- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/)
- [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [The Morning on PDPA dates](https://www.themorning.lk/articles/KlyUTsD2etA036HIMuLT), [Sri Lanka DPA](https://dpa.gov.lk/est.php)
- [App information: ICP filing](https://developer.apple.com/help/app-store-connect/reference/app-information/)
- [App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses)
- [Age assurance Q&A](https://developer.apple.com/support/age-assurance/)
- [Age requirements in Brazil, Australia, Singapore, Utah, Louisiana](https://developer.apple.com/news/?id=f5zj08ey)
- [Update on Texas](https://developer.apple.com/news/?id=8jzbigf4)
- Secondary, not primary legal texts: [Wellness app vs medical device under EU MDR](https://www.sanolabs.eu/blog/wellness-app-vs-medical-device-eu-mdr/), [Does leaving data on the device avoid GDPR?](https://www.chino.io/post/do-we-avoid-gdpr)
