# APP_STORE_PRE_LAUNCH_AUDIT.md

Audit of NOCTIS: Sleep & Recovery (iPhone + Apple Watch), version 1.0 (1), for App Store launch readiness.
Audited tree: branch `cleanup/release`, commit `d0f0f28` (2026-11-01). Read-only: no project file, configuration, dependency or behaviour was changed, nothing was installed, no network probe or load test was run. This file is the only thing written.

## 0. Scope note (read first)

- **Sections 1-11 were missing when sections 12-25 were written; they are now appended after section 25 as "Part 1".** (Original note: the brief said "continue the existing audit" but no earlier file existed in the repository, on any branch or stash, in the other worktree, or on disk.)
- The app is **local-only**: no server, no account of its own, no analytics SDK, no third-party package (`PRIVACY_REPORT.md` section 1; confirmed in code: no `URLSession`, `URLRequest`, `CloudKit`, `NWPathMonitor`, `MetricKit` or `WKWebView` in any shipped source; no `Package.resolved`; `project.yml` has one local package). That makes most of section 12 and parts of 13, 14, 19, 20 **not applicable by design**, not "passed". Each such row says so.
- Method: read `project.yml`, entitlements, `Info.plist`, privacy manifests, StoreKit config and the Store, Account, Coach, Deletion, analytics and recovery code; read every document under `Docs/`; ran `grep`/`find` over a `git archive` snapshot of the branch; counted placeholders in `Docs/site`. **Not run**: the app, any test suite, any build. Test results quoted below come from the project's own records (`QA_REPORT.md`, `QA_LEDGER.md`) and are labelled "reported", not re-verified.

### Confidence levels

| Level | Meaning |
| --- | --- |
| Confirmed | Seen directly in a file or command output in this audit. |
| Strong evidence | Follows from code read here plus documented platform behaviour; not exercised. |
| Potential risk | Plausible from the design; needs a test or a decision to settle. |
| Not verified | No access, or not inspectable from the repository. Never counted as a pass. |

## Verdict and blockers (written with sections 12-25)

**Not ready for App Store submission. Ready for TestFlight** (the project's own `RELEASE_READINESS.md` reaches the same verdict; this audit agrees and adds the items below).

A clean build and 2619 reported passing unit tests do not make the product production-ready. Nothing in this audit was run against a signed binary, a real device, a real Apple account, the live legal pages or a Sandbox purchase.

### Mandatory before submission (blockers)

| ID | Item | Confidence |
| --- | --- | --- |
| L-01 | Terms, Privacy Policy and support address are placeholders in the shipped code (`StoreConstants.swift:18-24`); `noctis.app` was reported (QA-180) to redirect to a domain-sale page. App Store Connect requires a working Privacy Policy URL. | Confirmed (code); live site Not verified |
| L-02 | The five draft pages in `Docs/site` still hold 5 `[[...]]` placeholders (`privacy` 2, `terms` 2, `support` 1) and are unpublished. | Confirmed |
| L-03 | No signing team, no registered bundle IDs or App Group, no signed archive, no App Store validation (QA-027). | Confirmed |
| L-04 | Subscriptions, agreements/tax/banking and sandbox testers do not exist yet in App Store Connect. | Not verified |
| L-05 | Owner sign-off on `PRIVACY_REPORT.md` and the App Privacy answers, including the open "support email" interpretation (Option A or B). | Confirmed open |
| L-06 | Review notes say Coach answers come from "fixed wording"; the code enables Apple's on-device generative model by default. Notes and listing must describe the real behaviour (X-06). | Strong evidence |
| L-07 | App Store screenshots are not usable as captured (mixed clock times; Insights, Coach, Tonight missing; no Watch screenshots). | Confirmed (docs) |
| L-08 | No run on a real iPhone, real Apple Watch, iOS 26.1, or with a real purchase and expiry. | Confirmed (docs) |
| L-09 | The source has **no git remote**: one Mac holds the only copy. | Confirmed |

### Recommended, not mandatory

Plan-expiry gap on widgets/Watch/Siri, no CI/CD, no crash or health monitoring beyond Apple's, no emergency kill switch, schema-upgrade path untested, Keychain survives uninstall, English-only with worldwide availability, trademark check, support procedures. Detail in the sections below.

## 12. Backend & Infrastructure

**Applicability: not applicable (no backend).** Nothing to audit for API, authN/authZ, object-level access, database indexes, injection, rate limiting, webhooks, queues, retries, server caching, server storage, environments, backups or DR. These are **not passed; they do not exist**.

| Check | Result | Confidence |
| --- | --- | --- |
| Any HTTP client, socket, WebView or remote endpoint in shipped code | None found. Only network-capable imports: StoreKit, AuthenticationServices, MessageUI, WatchConnectivity (`DataInventory.networkUses`). | Confirmed |
| Remote AI (`aiRemote`) | `RemoteModelProvider` and a privacy filter exist, tested, flag **off by default**, no transport/endpoint/key. Dead code today. | Confirmed |
| Embedded secrets | Grep for key/token/secret patterns outside tests and docs found nothing; `.gitignore` excludes `.env*`, `*.p8`, `*.p12`, `*.mobileprovision`. | Strong evidence (pattern scan, not a secret scanner) |
| Admin functionality | None. DEBUG launch flags (`-forceTier`, `-mockScenario`, `-mockSubscription`, `-mockStoreLoad`, ...) are compiled out of Release; `scripts/release_symbol_check.py` exit 0 on 7 binaries (reported, QA-183). | Strong evidence; re-run needed on the signed archive |
| Local persistence | SwiftData stores and JSON files, all `cloudKitDatabase: .none`. See section 16. | Confirmed |
| Future-server risk | If a server, analytics event or remote Coach is ever added, the privacy manifest, inventory, policy and tests must change (they are written to fail until they do). | Confirmed |

**Needs external verification:** none for a backend. If the owner plans one (account sync, remote Coach, server receipt validation), a separate audit is required before it ships.

## 13. Payments & Monetization

**Applicability: applicable.** Auto-renewable subscriptions via StoreKit 2 only. No external payment link, web checkout or alternative payment mechanism exists in the code. Not applicable: any external-purchase entitlement, alternative marketplace, or DMA distribution; none are used or claimed.

### What is implemented (Confirmed from code)

- Two products in one group, `com.noctis.app.premium.yearly` (1-week intro free trial) and `.monthly`; test file `Config/Noctis.storekit` (prices 39.99 / 6.99 are test values; the paywall reads the price from `Product`, never hard-coded, QA-143).
- `StoreManager.purchase`: handles `.success(.verified)` (finishes, refreshes), `.success(.unverified)` (fails with a message, transaction left unfinished), `.pending`, `.userCancelled`, `@unknown default`, and thrown errors.
- `EntitlementManager`: listens to `Transaction.updates` (renewals, refunds, Ask to Buy approvals, other-device purchases), reads `Transaction.currentEntitlements`, ignores unverified and revoked records, counts billing grace as Premium until its own end, treats family-shared ownership as Premium, orders overlapping refreshes (a stale answer cannot undo a refund), and schedules a refresh at the plan's end because StoreKit never announces expiry (QA-127).
- Restore: `AppStore.sync()` on the paywall and in Settings; outcomes `restored / nothingFound / failed`.
- Manage subscription: `manageSubscriptionsSheet` in Settings and Data management.
- Paywall carries price, period, trial length (from the intro offer), renewal sentence, Restore, Terms, Privacy, a way out, and the medical notice (QA-142, QA-143).
- Tier is a presentation gate only; gating never deletes user data.

### Findings

| ID | Finding | Confidence |
| --- | --- | --- |
| P-01 | **All verification is on-device.** No server receipt validation, no App Store Server Notifications, no server API, so no cross-device entitlement truth, refund/chargeback analytics, or win-back signal. Acceptable for a local-only app; a device with a tampered store, or a jailbroken device editing the cached tier, can show Premium locally. Low value to an attacker (no server cost, no content delivered remotely). | Strong evidence |
| P-02 | `EntitlementCache` stores the last tier as one `UserDefaults` word and the widget/Watch snapshot carries a plan flag. Used as a first-frame value until StoreKit answers (local call). Tampering gives local-only Premium UI. | Strong evidence |
| P-03 | **Plan expiry while the app is not running is not reflected on widgets, complications and Siri** until the app next runs (`POST_LAUNCH.md`, "KNOWN GAP"). A lapsed person keeps Premium widgets for days. Not a store violation; a revenue/trust leak. Needs a device and a real expiry to test. | Confirmed (documented) |
| P-04 | `renewal()` calls `Product.products(for:)` on every refresh; on failure it returns nil (grace/billing-retry nuance lost, tier still resolved from entitlements). Offline refresh therefore cannot show "payment problem" state. | Strong evidence |
| P-05 | Family Sharing is `familyShareable: false` in the test file; code supports family-shared ownership. The App Store Connect setting must be chosen on purpose and match (note in `APP_STORE_LISTING.md`). Behaviour with Family Sharing on is untested on a real account. | Not verified |
| P-06 | No refund-request sheet (`beginRefundRequest`), no offer-code redemption sheet, no promotional/win-back offers, no `AppTransaction` check. All optional; refunds go through Apple's page, which the support copy names. | Confirmed (absent), Info |
| P-07 | StoreKitTest cannot reproduce a declined Ask to Buy, billing retry/grace or a real expiry faithfully (QA-129). The purchase suite passed 3 of 3 reruns, 24 tests, 1 known issue (reported). Intermittent before QA-188. | Reported; sample small |
| P-08 | Price disclosure and trial wording come from StoreKit; the listing's subscription paragraph carries auto-renewal, 24-hour cancel and Terms link as Apple guideline 3.1.2 expects. App Store Connect needs per-product display name, description, localization and a paywall review screenshot. | Strong evidence; ASC Not verified |
| P-09 | Pricing, regional price tiers, tax, and agreements are owner/Apple-account items. | Not verified |

### Not verified (needs access)

Sandbox runs (purchase, cancel, expire with app closed, billing retry, grace, refund, restore on a second device, Family Sharing, Ask to Buy), TestFlight purchase, real App Store Connect product state, real prices. **Required access:** Apple Developer account, sandbox testers, an iPhone.

## 14. User-Generated Content & Trust

**Applicability: not applicable.** Users cannot publish, upload, message, comment, review or share content with other people. Confirmed: no network, no accounts of others, no feed. The only outward flows are the person's own: Export my data (file), Share this night (image), Contact support (mail). Coach is a private conversation with an on-device model, history kept on the device, no sharing (`POST_LAUNCH.md`: "Coach share" deferred).

| Item | Result | Confidence |
| --- | --- | --- |
| Reporting, blocking, moderation, community guidelines | Not required (no UGC to other users). | Confirmed |
| Age-rating answers | Draft says no UGC, no web access. The App Store age-rating questionnaire was revised by Apple for the iOS 26 cycle (new tiers and questions on health/wellness topics and chat features). **Answer it in App Store Connect and read the resulting rating**; the draft deliberately states none. | Not verified |
| Support/escalation for safety | Coach has a fixed crisis reply and a built-in helpline list (8 regions + generic 112) plus findahelpline.com. The list is hard-coded and flagged for owner verification in the source. | Confirmed; numbers Not verified |

## 15. Specialized App Category Compliance

Applicable categories and where each stands. **Confirmed** = the rule is in Apple's published guidelines or in the repo; **Legal review** = interpretation needed; this is not legal advice.

| Category | Applies? | Obligation | Status |
| --- | --- | --- | --- |
| Health & fitness (HealthKit, wellness scores) | **Yes** | Guideline 5.1.3 (health data: no ads/data mining, no storing in iCloud), 2.5.1 (HealthKit used for health purpose, usage strings), 1.4.1 (medical-type information must be accurate, disclose data/methodology where claims are made), privacy policy covering Health data. Read-only HealthKit, usage string matches the five kinds read (held by `PrivacyManifestTests`). No writes, no iCloud. | Code supports it. Policy unpublished (L-01/L-02). **Recovery/sleep-quality "scores" are proprietary heuristics, not clinically validated; copy says "not a medical device". Whether any copy implies diagnosis or medical accuracy is a Legal review item** (X-22). |
| AI-generated content | **Yes** (Coach, Apple's on-device model) | App Review notes should disclose; output filtered by `CoachSafetyValidator` (banned language, no digits outside tokens, hedging required, token facts only, medical question and crisis routes fixed). No remote model, no data leaves device. | Review notes inaccurate (L-06). Behaviour on real Apple-Intelligence hardware Not verified. |
| Crisis / mental-health-adjacent | **Partly** (Coach crisis route) | Provide helpful resources; avoid giving advice. Helplines hard-coded, English only. | Owner verification of numbers; localization deferred |
| Location tracking | No | No location API or usage string. | Confirmed |
| Social, dating, UGC, marketplaces, VPN, crypto, financial services, education/children | No | None of these features exist. Not a Kids Category app; no children's-data design. | Confirmed; **minimum age is the owner's call** (Legal review: health apps and minors, COPPA/GDPR-K) |
| Regulated services / medical device | **Legal review** | Not marketed as a device or for diagnosis; disclaimer present on welcome, paywall, About, Watch, Terms. A disclaimer does not by itself resolve a regulatory classification if the marketing implies a medical purpose (the draft keywords include `hrv`, `heart rate`). | Legal review |
| Sign in with Apple | Yes, optional | Guideline 4.8 only applies when a third-party/social login is offered; none is. Account deletion (5.1.1(v)) is covered by "Delete account and data". The sign-in has no function in the app (R69), which may draw an App Review question about its purpose. | Owner to confirm with App Review (their own item) |
| Data protection law (GDPR/UK GDPR special-category health data; Sri Lanka PDPA 2022; US state health-data laws) | **Legal review** | If the developer never receives data, controller obligations may be minimal, but the support email (user-sent), and any future telemetry, change that. | Legal review |
| Subscription/consumer auto-renewal laws | Legal review | Apple processes billing; the in-app disclosure follows Apple's pattern. State and regional rules (e.g., auto-renewal, cooling-off) may add requirements. | Legal review |

## 16. Data Lifecycle & Reliability

| Stage | What exists (Confirmed from code/docs) | Gap / risk | Confidence |
| --- | --- | --- | --- |
| Creation | Health data read on device; profile, alarm, wind-down in SwiftData `default.store`; journal and Coach history in their own stores; insights/reviews/snapshot as JSON. | None found. | Confirmed |
| Storage | Atomic writes, `completeFileProtection` for journal, Coach, insights, reviews, snapshot; widget/sounds files `afterFirstUnlock` on purpose; sensitive stores excluded from backup. | Default store (profile, alarm, wind-down) and `UserDefaults` **are in device backups** with standard protection. Owner decision item 3. | Confirmed |
| Sync / conflicts | No sync (`cloudKitDatabase: .none`, no iCloud entitlement). Watch gets a one-way summary via WatchConnectivity. | Multi-device consistency is N/A. Watch shows stale data labelled by age; wipe propagates to an away Watch. Not verified on hardware. | Confirmed; device Not verified |
| Migration | Every store opens through a `VersionedSchema` + `SchemaMigrationPlan`, but **all schemas are V1 and `stages` is `[]`** (`NoctisSchema.swift:21-23`, Journal, CoachHistory). | No upgrade path has ever run: the first schema change in 1.1 is untested territory. Corrupt/unreadable store is quarantined, not deleted, and the app starts empty (R65). | Strong evidence |
| Interruption | Writes atomic, old file kept on failure, no temp leftovers (QA-134); stores that fail to open are set aside whole; locked-device stores left in place and run in memory. Purchase finish is idempotent through `Transaction.updates`. | Interrupt during Delete-all: runs a sequence; resume behaviour after a kill mid-way was not found in code read here. | Potential risk |
| Export | JSON export (profile, prefs, journal text, etc.) to `tmp`, removed on leaving and at next start. | Export includes Journal text by design (owner item 8). | Confirmed |
| Deletion | Per-category deletes, Reset preferences, Delete all (also cancels AlarmKit alarm, wipes Watch via a stored delete-time), Delete account and data. | **Rows deleted ≠ bytes erased**: SQLite free pages can keep deleted text until overwritten (Coach store stayed ~111 KB). Delete-all removes the files. Policy says "deleted". Owner item 5. | Confirmed |
| Retention | Local until the person deletes; no server retention. Diagnostic log kept by iOS. | Policy must state this. | Confirmed |
| Account recovery / merging | N/A: no account of its own. | **Keychain item survives app uninstall on iOS.** After delete and reinstall the app can start "signed in" with no data until `refresh()` asks Apple; no first-run reset of the item was found. Harmless to data; confusing to people and to a reviewer who reinstalls. | Potential risk |
| Backup/restore | iOS backup/restore only. Keychain item is `ThisDeviceOnly`. | Restore to a new iPhone: profile restored, Journal/Coach/insights not (excluded) — by design, must be explained in the policy/help. | Strong evidence |
| Duplicate requests | Purchase/restore driven by StoreKit; refresh guarded by a ticket counter. | None found. | Confirmed |

## 17. Real-World Device & Network Testing

Simulator and device results are kept separate. **No physical-device verification exists.** The project's own `DEVICE_TEST_CHECKLIST.md` has no row ticked.

| Condition | Simulator (reported by the project) | Physical device |
| --- | --- | --- |
| Fresh install | `scripts/qa_fresh_install.sh` exists; onboarding captured (reported) | Not verified |
| App upgrade (1.0 → 1.1) | Cannot exist yet | Not verified; see migration in section 16 |
| iPhone sizes | 17 Pro Max, 17 Pro, SE: 617 tier-1 screens produced and viewed, 0 unverified (reported). iPad: **unsupported by design** (`TARGETED_DEVICE_FAMILY: 1`); Mac and Vision "Designed for iPhone" disabled. | Not verified |
| iOS versions | iOS 27 runtime only. **iOS 26.1-26.x never run** (QA-020). Deployment target 26.1 chosen for AlarmKit/tab accessory APIs. | Not verified |
| Poor network / airplane mode / disconnection | N/A to NOCTIS code (no requests, enforced by a UI no-requests walk, QA-135). StoreKit behaviour offline not observed. | Not verified |
| Permission denial / revocation (Health, notifications, AlarmKit) | Denied and revoked mid-session states exist and are tested (QA-121) | Not verified; Apple Health sheet behaviour with 3-vs-5 kinds (below) |
| Low storage / full disk | Atomic-write failure paths tested (QA-134) | Not verified |
| Background / foreground / termination / restart | Clock stops and restarts on scenePhase; notification reschedule on active; cold-launch notification taps viewed (QA-133, simulated) | Not verified (real delivery, background delivery, AlarmKit, Live Activity, Watch) |
| Expired sessions | Plan expiry while app open tested (QA-127). Sign in with Apple revoked state tested with fakes. | Real expiry Not verified |
| Time-zone / clock changes | DST in 4 zones, midnight rollover, clock jumps, weekday-first regions: 12 tests pass (QA-123 to 126, reported) | Not verified |
| Interrupted uploads/downloads | N/A | N/A |
| Accessibility | Large text: tier-1 AX3/AX5 on SE and 17 Pro produced; **about 26 OPEN minor layout rows remain "fixed in source, not re-photographed"** (QA_REPORT section 1). Tier C (Reduce Motion, Increase Contrast, Bold Text, Smart Invert) **not run on the final build**. VoiceOver traversal tests written, **not run** (QA ledger 3.7). | Not verified |
| Dark Mode | Supported; A-dark captured | Not verified |

**Potential risk (X-26):** onboarding requests Health access for 3 kinds (sleep, heart rate, HRV) while the app's authorization check asks about 5. The project's own report says Home/Sleep/Recovery may keep showing "Connect Apple Health" until the person connects again (`PRIVACY_REPORT.md` section 6 item 2). Confirmed in code (`HealthScreen.requestedKinds`); the user-visible outcome needs a real Health store to settle.

## 18. Internationalization & Localization

| Check | Finding | Confidence |
| --- | --- | --- |
| Languages | **English only.** Six string catalogs, each has only `en` (checked). Settings Language row stays hidden until a second localization exists. Sinhala/Tamil are deferred. | Confirmed |
| Right-to-left | Declared not a v1 language (QA-085). Open RTL layout bugs exist (QA-081, 083, 086, 087); they only matter if an RTL language is added. | Confirmed |
| Text expansion | DoubleLength/Bounded pseudolanguage runs found clipped text (QA-082, QA-084, others); source fixes listed, many not re-photographed. | Confirmed (reported) |
| Dates, numbers, currency | `NoctisFormat` and StoreKit price display use the device locale; paywall price comes from the store (no hard-coded currency). | Strong evidence |
| Calendars | Several engines build `Calendar(identifier: .gregorian)` (Sleep night keys, Home, Tonight, Reviews). Sleep-night keys use UTC gregorian by design. Users on non-Gregorian system calendars (Buddhist, Islamic, Persian) may see Gregorian-based weeks/months in reviews while system UI is not. | Potential risk |
| Time zones | DST and zone-change tests exist (reported). Night key and notification schedules anchored to local time. | Strong evidence |
| Coach language | Router patterns, scripted text, banned-word list, crisis copy are English only. In a non-English locale Coach would still run English. | Confirmed |
| Crisis resources | 8 regions + generic 112; owner-flagged for verification; Sri Lanka listed first. Regions without an entry get generic 112 + findahelpline.com. | Confirmed; numbers Not verified |
| Storefront availability | App Store listing says English; no territory restriction chosen. Availability in all storefronts with an English-only, crisis-sensitive Coach is an owner decision. | Not verified |
| Regional legal | Health-data, consumer and privacy rules vary by territory (section 15, 23). | Legal review |

## 19. Analytics, Monitoring & Operations

| Capability | State | Confidence |
| --- | --- | --- |
| Analytics | None sent. `NoctisAnalytics` writes six events (`paywall_viewed`, `plan_selected`, `trial_started`, `purchase_completed`, `paywall_dismissed`, `onboarding_completed`) with plan ids to the unified log, `privacy: .public`. They never leave the phone unless the person shares a sysdiagnose. Duplicate events were not tested. | Confirmed |
| Sensitive data in telemetry | None found: other log lines carry enum names, error domain/code, alarm state; Coach logs an outcome code only. | Confirmed (grep of `Logger` calls) |
| Crash reporting | None in-app. Only Apple's opt-in crash/metrics reports (Xcode Organizer, TestFlight). `MetricKit` is not used. | Confirmed |
| Performance monitoring | Signposts exist (`NoctisSignpost`: tab switch, Watch complication budget, background refresh). Numbers are simulator smoke numbers, not device budgets (QA-122). | Confirmed |
| Backend health, alerting | N/A (no backend). **No alerting of any kind**: if purchases fail in production nobody is told. | Confirmed |
| User journey / funnel | None measurable: no paywall conversion, no onboarding drop-off, no retention data. Only App Store Connect's own aggregate analytics. | Confirmed |
| Support channel | One mailbox (`support@noctis.app`, placeholder) via `MFMailComposeViewController`/`mailto:`; Support page drafted. No ticketing, SLA, canned replies or App Review response procedure documented. | Confirmed |
| Incident response | No written procedure (who decides, how to pull a build, how to expedite a fix). | Confirmed (absent) |

**Assessment:** the app can be maintained, but cannot be *monitored* after launch beyond Apple's dashboards and user email. Without adding any SDK, the cheap options are Xcode Organizer crash/hang reports, App Store Connect Sales & Trends/Subscription reports, a written support routine, and (if desired) MetricKit locally. Introducing any collection changes the privacy declarations and tests.

## 20. Third-Party & Software Supply Chain

| Check | Result | Confidence |
| --- | --- | --- |
| Dependencies | **Zero external dependencies.** One local Swift package (`Packages/NoctisKit`), no remote `.package(url:)`, no `Package.resolved`, no CocoaPods/Carthage, no binary frameworks, no XCFrameworks. | Confirmed |
| Transitive | None. | Confirmed |
| Third-party SDKs / signatures / known CVEs / unmaintained | N/A. | Confirmed |
| Privacy manifests | 5 `PrivacyInfo.xcprivacy` (app, widgets, alarm, Watch app, Watch widgets). App: no tracking, no collected data, `UserDefaults` `CA92.1`. Held by `PrivacyManifestTests` and `nm -u` on Release binaries (reported, QA-029). | Confirmed |
| Required-reason APIs | Audit lists file timestamp, boot time, disk space and keyboards as unused; scanned by test. Not re-run here. | Reported |
| Apple frameworks that need declarations | HealthKit, AlarmKit, FoundationModels (Apple Intelligence), WatchConnectivity, AuthenticationServices; entitlements and usage strings present. | Confirmed |
| Licenses | No `LICENSE`/`NOTICE` file in the repo. No third-party code to attribute. | Confirmed |
| Build-tool supply chain | `xcodegen` (generates `project.pbxproj`, which is also committed), Python QA scripts, `swift-format`. Versions are not pinned in the repo. | Confirmed |
| Mobile security standards | OWASP MASVS: storage (file protection, backup exclusion, Keychain `ThisDeviceOnly`), crypto (none own), auth (optional SIWA), network (no traffic), platform (single URL scheme `noctis://` with an allow-list router, App Group files), code quality (strict concurrency complete, 0 warnings reported). A MASTG dynamic test (jailbreak, binary tamper, debugger) was **not** performed. | Strong evidence; dynamic Not verified |
| URL scheme | `noctis://recovery|sleep|tonight|wind-down|bedtime` only; nothing else accepted (R44). Unauthenticated deep link can only open screens. Confirmed in plist and docs; router tests reported. | Strong evidence |

## 21. CI/CD & Release Engineering

| Area | State | Confidence |
| --- | --- | --- |
| Build automation | **None.** No `.github`, no Fastlane, no CI config. `xcodebuild` commands live in docs and `project.yml` comments. | Confirmed |
| Test automation | Scheme `NOCTIS-Unit` (test plan over time zone/region/clock/first-weekday) and `NOCTIS-Store`, run by hand. 2619 tests in 355 suites reported passing on 2026-11-01 at 6105f16 (not re-run; HEAD is `d0f0f28`, docs-only since). | Reported |
| Release workflow | Manual, documented in `Docs/store/SUBMIT_CHECKLIST.md`. | Confirmed |
| Environment separation | Debug/Release configs; DEBUG flags stripped from Release (symbol check). StoreKit config for testing only; no staging/production backend to separate. | Confirmed |
| Secrets | None needed today. `.gitignore` is sound. | Confirmed |
| Signing automation | **None.** No team in `project.yml`; unsigned archive built; archive command in checklist uses `-allowProvisioningUpdates` with the owner's team. | Confirmed |
| Version management | `MARKETING_VERSION 1.0`, `CURRENT_PROJECT_VERSION 1` hand-edited in `project.yml`; no tags (`git tag` empty); no build-number bump step. App Store Connect rejects a repeated build number. | Confirmed |
| Reproducibility | `project.pbxproj` is generated *and* committed: drift between `project.yml` and the pbxproj is possible. Toolchain versions unpinned. | Strong evidence |
| Artifact storage | `*.xcarchive`, `*.ipa`, `*.dSYM/` are git-ignored. **No stored archives or dSYMs**, so a crash from a shipped build could not be symbolicated unless Xcode's Organizer keeps the archive on this Mac. | Strong evidence |
| Approvals / rollback | None formal. App Store has no binary rollback; recovery is a new build with expedited review, or phased release pause. No documented plan. | Confirmed |
| Source safety | **No remote** (`git remote` empty), 135 commits, one clone. Two worktrees/branches exist locally. | Confirmed |

**Verdict:** there is no reliable, repeatable release process yet; there is a thorough manual checklist.

## 22. App Store Product Page & Submission

Material under review: `Docs/store/APP_STORE_LISTING.md`, `SUBMIT_CHECKLIST.md`, `Docs/site/*`.

| Item | Finding | Confidence |
| --- | --- | --- |
| Name / subtitle | "NOCTIS: Sleep & Recovery" (24/30), "Sleep and recovery, on device" (29/30). Trademark and name availability in App Store Connect Not checked. | Not verified |
| Description accuracy | Matches code in the areas read (on-device, no account, read-only Health, free/Premium split from `FeatureTable`, subscription terms). **One mismatch:** Coach is described as "runs on your iPhone" (true) while review notes say answers are "fixed wording" (X-06). Sentence "Siri phrases" etc. rely on features that were only simulator-checked. | Strong evidence |
| Keywords | 100-char list includes `hrv`, `heart rate`: relevance is fine; medical-claim sensitivity is a review item (section 15). | Not verified |
| Categories | Health & Fitness primary, Lifestyle secondary. | Confirmed (draft) |
| Icon | 1024x1024, no transparency, light and dark (reported). Not viewed in this audit. | Reported |
| Screenshots | **Not ready** (L-07). Watch screenshots required and absent. No app previews planned. | Confirmed |
| Age rating | Questionnaire unanswered; revised by Apple. | Not verified |
| Privacy policy | Draft only, unpublished, 2 placeholders on the page itself (L-02). | Confirmed |
| Support info / copyright | Support page drafted, mailbox does not exist yet; copyright holder name is `[[OWNER_NAME]]`. | Confirmed |
| App Privacy declarations | Draft: Data Not Collected, no tracking. Depends on the support-email interpretation (Option A vs B) and on the owner reading the policy. | Confirmed open |
| In-app purchase metadata | Table drafted (ids, names, periods, trial). Needs descriptions, localizations, prices and review screenshots in ASC. | Not verified |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO`; code links no CryptoKit/CommonCrypto/Security beyond the Keychain item (`import Security` in `AccountStore` is the Keychain API, which falls under the exemption for OS-provided cryptography per the project's reading). Owner confirms in ASC. | Strong evidence; Legal review for the exemption wording |
| Review notes | Drafted, with Health explanation, subscription steps, permissions, medical notice. Needs the Coach correction (L-06) and a statement that Sign in with Apple is optional and local. | Confirmed |
| Reviewer credentials / demo account | None needed: no account. Without Health data the reviewer sees empty/learning states plus a labelled Sample night; reviewer must add Health samples to see Home/Sleep/Recovery. **Reviewers often cannot or will not add Health data**; consider making that path obvious. | Strong evidence |
| Backend availability during review | N/A. | Confirmed |

## 23. Legal, IP & Business Readiness

All rows are findings for the owner and counsel. None is legal advice.

| Item | Finding | Confidence |
| --- | --- | --- |
| Terms of Service | Draft adds to Apple's standard EULA (allowed by the code: `appleStandardTerms`). Unpublished; placeholders. | Confirmed |
| Privacy policy | Draft consistent with the code. Must state: HealthKit use, background delivery, the diagnostic log, backups, deletion semantics, WatchConnectivity transfer, support email. Several of these are listed as owner decisions in the privacy report. | Confirmed |
| Copyright / trademark | "NOCTIS" name, domain `noctis.app` (not owned per QA-180), icon and wordmark: no clearance search recorded. | Not verified |
| Unlicensed assets | No font files, no audio files, no bitmap/music assets found; sounds are synthesized in code (R31); recorded meditation/forest/night sounds deliberately deferred for licensing. Icon and artwork authorship Not verified. | Strong evidence |
| Third-party API terms | Apple frameworks only (Apple Developer Program License Agreement and HealthKit/AlarmKit/Foundation Models terms apply). `findahelpline.com` is linked, not scraped. | Confirmed |
| Data processing | No processors. Email to support makes the owner a recipient of whatever the user writes. | Strong evidence |
| Consumer protection | Auto-renewal disclosure follows Apple's pattern; regional rules Legal review. Refunds via Apple. | Legal review |
| Support & complaints | One mailbox; no stated response time; no complaint procedure. Some regions require a contact point and response time. | Legal review |
| Medical disclaimer | Present in 6 places. A disclaimer does not cure marketing that implies a medical purpose. | Legal review |
| Business entity | Owner name, address, tax and banking details are placeholders / not in the repo. | Not verified |

## 24. Launch & Post-Launch Readiness

| Item | Mandatory? | State |
| --- | --- | --- |
| Support readiness (working inbox, published support page) | **Mandatory** | Absent (L-01, L-02) |
| Crash monitoring | Recommended | Only Apple's Organizer; needs dSYM/archive retention (section 21) |
| Production monitoring / backend capacity / DB recovery | N/A | No backend |
| Incident response | Recommended | No written procedure |
| Feature flags / emergency disable | Recommended | Only compile-time `AIFlags` (`aiCoach`, `aiAppleIntelligence`, `aiRemote`); **no remote kill switch**. Disabling a faulty feature (e.g. Coach generative path) needs a new build and expedited review. |
| Release rollback | Recommended | None possible beyond new build / pause phased release |
| User feedback collection | Recommended | Support email and App Store reviews only |
| App Store review response readiness | Recommended | None documented |
| Post-launch update strategy | Recommended | `POST_LAUNCH.md` is a good deferred list, but no schema-migration test exists for 1.1 (section 16) and `CURRENT_PROJECT_VERSION` is manual |
| Phased release | Recommended | Not configured (App Store Connect setting) |
| Device pass, signed archive, TestFlight overnight run | **Mandatory** | Not done (L-03, L-08) |

## 25. Evidence, Coverage & Limitations

### Additional findings register (not in blockers)

| ID | Finding | Confidence | Severity |
| --- | --- | --- | --- |
| X-06 | Review notes: "Coach answers are made on the iPhone ... and fixed wording". Code: `AIFlags.aiAppleIntelligence` defaults `true`, `FoundationModelsProvider` generates drafts via `SystemLanguageModel` on supported devices; a validator filters them. Notes and `PRIVACY_REPORT` statement should say "Apple's on-device model, filtered". | Strong evidence | Major (review rejection risk) |
| X-09 | Plan-expiry gap on widgets/Watch/Siri (P-03). | Confirmed | Minor |
| X-10 | No CI, no automation, manual version bump, generated pbxproj committed (section 21). | Confirmed | Medium |
| X-11 | Keychain item outlives uninstall (section 16). | Potential risk | Minor |
| X-12 | Public diagnostic log of plan ids (owner item 7). | Confirmed | Info |
| X-13 | No in-app crash/health monitoring; no dSYM retention. | Confirmed | Medium |
| X-14 | English-only, worldwide storefronts, English crisis copy, Gregorian calendar assumption. | Confirmed / Potential risk | Medium |
| X-15 | Deleted rows remain in SQLite free pages; app-switcher snapshot can show scores/journal text (owner items 5, 6). | Confirmed | Minor |
| X-16 | Migration plans have zero stages; no upgrade test possible before v1 ships. | Strong evidence | Medium |
| X-17 | Sign in with Apple has no function; may draw a review question. | Potential risk | Minor |
| X-18 | Minimum iOS 26.1 limits audience; 26.x never run. | Potential risk | Business |
| X-19 | No support SLA, no incident or review-response procedure. | Confirmed | Medium |
| X-20 | No remote feature kill switch. | Confirmed | Medium |
| X-21 | No trademark/domain/name clearance recorded. | Not verified | Medium |
| X-22 | Recovery/sleep scores are non-clinical heuristics; marketing and keywords must not imply medical accuracy. | Legal review | Medium |
| X-23 | `.unverified` purchase leaves the transaction unfinished; StoreKit redelivers it, so nothing is lost. Not a defect. | Strong evidence | Info |
| X-24 | No refund/offer-code sheets, optional features. | Confirmed | Info |
| X-26 | Onboarding asks 3 Health kinds, app checks 5; possible repeat "Connect Apple Health" (section 17). | Confirmed (code) / outcome Not verified | Medium |
| X-27 | ~26 open minor layout rows ("fixed in source, not re-photographed"); Tier C accessibility and VoiceOver traversal not run on the final build; QA-087/089/090/092/115 etc. | Confirmed (reported) | Minor-Medium |
| X-28 | Docs claim 2619 tests pass at `6105f16`; not re-run at `d0f0f28` (docs-only since). | Reported | Info |

### Coverage per audit category

"Inspected" means read in this audit. "Tests performed" means I ran it; I ran no tests. Every row inherits the global limit: **no running app, no build, no network, no Apple account, no device, no counsel.**

| § | Category | Inspected (files / systems) | Methods | Tests performed here | Passed | Failed / open | Not verified; access needed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 12 | Backend & infra | whole source tree, `project.yml`, entitlements, plist | grep, read | none | No backend present (N/A) | none | Any future backend; N/A today |
| 13 | Payments | `StoreManager`, `EntitlementManager`, `EntitlementClient`, `EntitlementCache`, `StoreConstants`, `Noctis.storekit`, `PaywallScreen`, listing | read, grep | none | Code paths for success, pending, cancel, unverified, revoked, grace, family, restore, expiry timer exist | P-01..P-06 | Sandbox, TestFlight, ASC products, tax/banking, Family Sharing (Apple account, device) |
| 14 | UGC | source, docs | grep, read | none | N/A (no UGC) | none | Age rating (ASC) |
| 15 | Category compliance | docs, Coach code, helplines, manifests | read | none | Controls exist for HealthKit, AI, crisis | X-06, X-22 | Counsel; App Review feedback |
| 16 | Data lifecycle | `AccountStore`, `StoreRecovery`, schemas, stores, `PRIVACY_REPORT`, `POST_LAUNCH` | read | none | Atomic writes, quarantine, backup exclusion, protection classes present | X-11, X-15, X-16 | Real-device kill mid-delete, backup/restore, upgrade run (device, v1 release) |
| 17 | Device/network | `DEVICE_TEST_CHECKLIST`, `QA_*` docs, `project.yml` | read | none | Simulator evidence is reported only | X-26, X-27 | **All physical-device rows**; iOS 26.1; Apple Watch (devices) |
| 18 | i18n | catalogs, helplines, formatters, ledger | python catalog scan, grep | catalog language count | English catalogs complete for en | X-14 | Native translators, regional counsel |
| 19 | Analytics/ops | `NoctisAnalytics`, all `Logger` uses, docs | grep, read | none | No sensitive telemetry found | X-13, X-19 | Production dashboards (ASC, Organizer) |
| 20 | Supply chain | `Package.swift`, manifests, repo tree | find, read | none | No dependencies | no LICENSE file; tools unpinned | Dynamic MASTG tests; signed binary scan |
| 21 | CI/CD | repo root, `scripts/`, `.gitignore`, git metadata | ls, git | none | Manual checklist present | X-10, L-09 | Team signing, CI service |
| 22 | Submission | `Docs/store/*`, `Docs/site/*` | read, grep | placeholder count | Drafts complete | L-02, L-06, L-07 | ASC state, screenshots, rating |
| 23 | Legal/IP | docs, assets search | find, read | none | No unlicensed assets found | X-21 | Counsel, trademark search |
| 24 | Launch readiness | docs | read | none | `POST_LAUNCH.md` exists | X-19, X-20 | Owner decisions |
| 25 | Evidence | this file | n/a | n/a | n/a | n/a | n/a |

### Audit coverage matrix: access status

| Area | Access in this audit | Status |
| --- | --- | --- |
| Source code (branch `cleanup/release`, `d0f0f28`) | Read-only snapshot | Inspected (selected files; not every one of 581 Swift files was read) |
| Backend / infrastructure | **Does not exist** | N/A |
| Apple Developer account / App Store Connect | **No access** | Not verified |
| Physical iPhone / Apple Watch | **No access** | Not verified |
| Real StoreKit / Sandbox / TestFlight | **No access** | Not verified |
| Live websites (`noctis.app`, legal pages) | **Not probed** (read-only, no network use) | Not verified (QA-180 relied on) |
| Third-party services | None used | N/A |
| Legal / regulatory counsel | **No access** | Legal review items listed |
| Test execution | **Not run** | Project-reported results only |
| Release binary / signed archive | **Not available** | Not verified |

### Notes on rigor

- No area is given a passing score where it could not be tested. "N/A" means the thing does not exist, not that it was checked.
- Source for "reported" results is the project's own documents; they were not independently reproduced.
- Not read in full: most of `APP_RULES.md` (396 lines), the whole of `QA_LEDGER.md` (307 lines, scanned by status), the 581 Swift files (searched, not read), `Tests/`, `Localizations/needs-translation.csv`.

## Stopped

Sections 12-25 complete. Part 1 (sections 1-11) follows below, with the consolidated findings and updated readiness at the end of the file. No fixes made.


---

# PART 1: Sections 1-11 (appended)

Written after sections 12-25 (above), by the same read-only method plus **isolated builds and tests** described in section 1.3. Sections 12-25 are not repeated; where a finding there is relevant, it is cited by its ID (L-, P-, X-). IDs below are new and unique: `OV` overview, `JR` journeys, `ARCH`, `CQ`, `SEC`, `PRIV`, `UX`, `PERF`, `FUNC`, `COMP`, `REL`.

Each finding gives: severity (Blocker, Major, Minor, Info), **Blocks release** (Yes / No / Decide), confidence (Confirmed, Strong evidence, Potential risk, Not verified), file and line, evidence, impact, recommended solution. Nothing was fixed.

## 1. Product Overview & Audit Summary

### 1.1 Product

NOCTIS: Sleep & Recovery. An iPhone (portrait) and Apple Watch app that reads sleep, heart rate, resting heart rate, HRV and respiratory rate from Apple Health (read only) and shows: how you slept, a Recovery score, tonight's bedtime, a wake alarm, a wind-down, breathing, meditation, synthesized sleep sounds, insights, weekly and monthly reviews, and "Coach" (questions about your own numbers, answered on-device). Free tier plus one subscription group (yearly with a one-week trial, monthly). Everything is local: no server, no account of its own, no third-party code.

### 1.2 What the repository contains (counted in this audit)

| Item | Value |
| --- | --- |
| Shipped targets (project.yml) | iPhone app `NOCTIS` (`com.noctis.app`), Home/Lock Screen widgets + controls + Live Activity `NOCTISWidgets`, alarm snooze widget `NoctisAlarmWidget`, Watch app `NOCTISWatch`, Watch complications `NOCTISWatchWidgets`; test targets `NoctisStoreTests`, `NoctisUITests`; one local package `NoctisKit` (29 library modules + a QA-only `QACatalog`) |
| Swift files | 411 shipped (App 2, Widgets 4, Watch 9, NoctisKit 396); 168 test files (package 140, app-level 28). The "581" figure used earlier = 411 shipped + 168 test + 2 others (`Package.swift`, `QA/QACatalog/ScreenCatalog.swift`); it is not a count of shipped files |
| Lines of Swift | about 76,100 shipped, about 44,900 test |
| Tests (declared) | 2,643 `@Test` in the package and app-level tests, 219 XCTest functions, 2 Swift Testing suites declared with `@Suite` (the rest are inferred suites) |
| Toolchain | Xcode 27.0 (27A266a), Apple Swift 6.4, Swift 6 language mode, complete strict concurrency; deployment iOS 26.1, watchOS 26.0 |
| External dependencies | none |
| Built app size | 58 MB (`NOCTIS.app`, Release, unsigned, includes the embedded Watch app and three extensions) |

### 1.3 Method and what was actually run

- **Source snapshot.** `git archive cleanup/release` (commit `d0f0f28`) extracted outside the repository into the session scratchpad. **All builds, tests, linting and the symbol check ran on that snapshot, not on the working tree**, so no project file, DerivedData or generated file was written inside the repository. For C4b a second copy of the same snapshot was made at `~/.noctis-audit-snapshot` (outside the repository, 1.0 GB with its DerivedData); both copies were left in place and can be deleted by the owner. A second worktree (`claude/charming-liskov-749f7b`, an older Recovery-phase branch with uncommitted edits by another session) was **not** audited and was not touched.
- **Files individually read.** Not all 411 shipped files. Read in full or in large part: `project.yml`, `Package.swift`, the entitlements, Info.plists and privacy manifests, `StoreManager`, `EntitlementManager`/`Client`/`Cache`, `StoreConstants`, `AccountStore`, `DataManager`, `DataWiring` (part), `StoreRecovery` (header), `NoctisAnalytics`, `WidgetURLRouter`, `HealthKitProvider` (authorization and background delivery), `NoctisApp`, `RootView` (scenePhase part), `FeatureTable`, Coach provider and validator headers. Everything else was inspected by search (`grep`, counts, `find`), by the tooling output below, or via the project's own documents. **Not read: the bulk of the 396 package files, the 168 test files, and all Watch/Widgets view code.**
- **Commands run (all read-only with respect to the repository):**

| # | Command (abridged) | Result |
| --- | --- | --- |
| C1 | `xcodebuild build -project Noctis.xcodeproj -scheme Noctis -configuration Release -destination generic/platform=iOS -derivedDataPath <scratch>/dd-release CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED**, exit 0, **0 compiler warnings** (`grep -c 'warning:'` on the log). **Verified here.** |
| C2 | `python3 -I scripts/release_symbol_check.py <Release-iphoneos>` | **Exit 0**: 7 binaries, 0 hits, 112 `#if DEBUG` blocks in 44 files, 293 DEBUG-only names and 110 strings searched. **Verified here** (the project's QA-183 result reproduced on a fresh build). |
| C3 | `plutil -p NOCTIS.app/Info.plist`; `find NOCTIS.app -name PrivacyInfo.xcprivacy` | `MinimumOSVersion 26.1`, version 1.0 (1), `DTSDKName iphoneos27.0`, usage strings present; **5 privacy manifests** in the built bundle (app, widgets, alarm, Watch app, Watch widgets). **Verified here.** |
| C4 | `xcodebuild test -scheme NoctisKit-Package -destination iPhone 18 Pro (iOS 27.0 simulator) -derivedDataPath <scratch>/dd-unit SWIFT_EMIT_LOC_STRINGS=NO` | Run 1 (snapshot under the `/tmp` symlink, scratchpad): stalled after 2,941 passes, 18 source-scanning guard tests failed from a path artifact (CQ-06), and I interrupted it (`TEST INTERRUPTED`, exit 75); its cause for stalling was not established. **C4b**, same command from a non-symlinked copy outside the repository (`~/.noctis-audit-snapshot`, DerivedData and result bundle inside it): **TEST SUCCEEDED, 2,619 tests in 355 suites passed in 658.9 s**, exit 0. iOS 27.0 simulator (iPhone 18 Pro) only. **Verified here (C4b).** |
| C5 | `swiftlint lint --no-cache --reporter json` over `App Widgets Watch Packages/NoctisKit/Sources` | 4,043 findings under **SwiftLint's default rules** (the project has no `.swiftlint.yml`; it formats with `.swift-format`). Treated as an indicator only. See CQ-01. |
| C6 | `grep`, `find`, `wc`, `sips -g` on icons | counts used throughout. App icons 1024x1024, no alpha (Light, Dark; Watch icon present). |

- **Not run:** the `NOCTIS-Store` purchase scheme (needs the app host and StoreKit test session; would exceed the time box beside C4), the **UI test suite and the QA matrix** (hundreds of simulator launches), Instruments, any physical device, any signed archive, `xcodegen generate` (would rewrite the project; not needed). Simulator runtime available: **iOS 27.0 and watchOS 27.0 only**; nothing could be run on iOS 26.x.

### 1.4 Verified here versus reported by the project

| Result | Status |
| --- | --- |
| Release build succeeds, 0 warnings | **Verified here (C1)** |
| No DEBUG scaffolding in Release binaries | **Verified here (C2)** |
| Built bundle structure (one app, Watch app embedded, 2 iPhone extensions + 1 Watch extension, 5 manifests, min iOS 26.1) | **Verified here (C3)** |
| Package unit suite | **Verified here (C4b): 2,619 tests in 355 suites passed, 658.9 s, TEST SUCCEEDED**; the same counts the project reported. iOS 27 simulator only; not run on iOS 26.x or a device |
| 2,619 tests in 355 suites passed on 2026-11-01 at 6105f16 | Reported (`QA_REPORT.md`); HEAD is `d0f0f28`, docs-only since |
| `NOCTIS-Store` purchase scheme: 3 of 3 runs, 24 tests, 1 known issue | Reported (QA-188) |
| UI/QA matrix: 617 tier-1 combinations produced and viewed; 814 phone + 24 Watch pictures viewed | Reported (`QA_COVERAGE.md`); pictures not re-viewed here |
| Memory leak run (46 leaked blocks, 1,472 bytes), TSan UI run, 730-night timings | Reported (QA-044, QA-049, QA-122), simulator only |
| Ledger status at HEAD (193 rows, counted by this audit from `QA_LEDGER.md`) | Reported: blocker 1 FIXED; major 12 FIXED, 1 VERIFIED, **2 OPEN**; minor 73 FIXED, 13 ACCEPTED, **18 OPEN**, 4 UNVERIFIED; info 69 (FIXED 4, ACCEPTED 16, OPEN 1, PASS 20, UNVERIFIED 2, VERIFIED 26) |

### 1.5 Audit summary (all sections 1-25)

**Engineering quality is high for a v1; release readiness is low because everything outside the code is open.** The code builds clean, ships no debug scaffolding, has no dependencies, keeps data on the device, and has an unusual depth of tests and written rules. What stands between it and an App Store submission is almost entirely owner/Apple-account/legal/device work (section 24 and the blockers in the verdict at the top of this file), plus a small number of code-adjacent decisions listed in the consolidated findings at the end of this part.

| Dimension | Assessment |
| --- | --- |
| Build health | Good (verified) |
| Architecture | Good, with one over-large composition root |
| Security | Good for a local-only app; two small hardening items |
| Privacy | Good design; documents and policy unpublished; three owner decisions open |
| Accessibility and UX | Extensive work, but untested configurations remain and shipped code ignores three accessibility settings |
| Performance / stability | Plausible; **no device numbers exist** |
| Functional completeness | Complete for the stated scope; verified only on simulator |
| iOS compatibility | Compiles for 26.1; **never run on iOS 26.x** |
| Release configuration | Correct in the repo; signing, IDs, versions, archive not done |

No new code defect that blocks release was found. Major items added in this part: PRIV-01 (same root as X-26), UX-03, PERF-01, FUNC-01, COMP-01, REL-01; the rest are Minor or Info. See the consolidated list.

---

## 2. Application Feature Inventory & User Journeys

### 2.1 Feature inventory (from `FeatureTable.swift`, `AppTab.swift`, target sources)

Five tabs (`AppTab.swift:4`): Home, Sleep, Recovery, Insights, Coach. Tier from `FeatureTable.tier(of:)` (`PremiumKit/FeatureTable.swift`), which has 44 features (counted from the `Feature` enum).

| Area | Free | Premium | Where it lives |
| --- | --- | --- | --- |
| Recovery | Today (with how it was built), 7 days | 30 and 90 days, factor detail | `RecoveryFeature`, `RecoveryKit` |
| Sleep | Last 3 nights, week, quality score | Month, 14-night picker, quality factors, consistency/balance/timing detail | `SleepFeature`, `SleepKit`, `SleepAnalysisKit` |
| Insights | Featured, most recent other | All, records, history, category filters | `InsightsFeature`, `InsightsKit` |
| Reviews | Weekly cover | Full weekly, monthly | `ReviewKit`, `InsightsFeature` |
| Coach | 3 questions a day, history | Unlimited | `CoachKit`, `CoachFeature` |
| Tonight / night | Single bedtime, alarm (AlarmKit), breathing, reflect/journal | Personal window, wind-down session, meditation | `NightKit`, `NightFeature`, `BreathingKit`, `JournalKit` |
| Sounds | 3 sounds (synthesized in code) | 3 more | `SoundKit`, `SoundCatalog` |
| Widgets | Small, Lock circular | Medium/Large, other Lock | `NoctisWidgetKit`, `Widgets/Home` |
| Apple Watch | Recovery/Sleep pages, recovery complication, breathing | Heart and Tonight pages, other complications | `Watch/*`, `NoctisWatchKit` |
| Siri / Shortcuts / Controls | Recovery, sleep, bedtime | Start wind-down, Coach beyond free | `NoctisIntentKit`, `App/NoctisShortcuts.swift` |
| Live Activity | wind-down on Lock Screen, Dynamic Island, Watch Smart Stack | | `Widgets/Home/NoctisWindDownActivity.swift` |
| Profile / Settings | Profile, goals, notifications, Apple Watch settings, Privacy Center, Data management (export, per-category delete, delete all, reset), Help, About, Subscription | | `ProfileFeature` |
| Account | Optional Sign in with Apple, local only | | `NoctisCore/Account` |

Extension surfaces: Home Screen and Lock Screen widgets, two Control Center controls, one Live Activity, alarm snooze countdown, Watch app (five pages), four complications. URL scheme `noctis://`.

### 2.2 User journeys (names from the files in `OnboardingFeature`, `AppRoot`, `ProfileFeature`; exact step order was not traced in code)

1. **First launch:** Welcome (optional Sign in with Apple) → name → goal → sleep rhythm → Apple Health permission (asks 3 kinds) → notifications → labelled Sample night → plan building → plan ready → paywall → Home. (`WelcomeScreen`, `NameScreen`, `GoalScreen`, `RhythmScreen`, `HealthScreen`, `NotificationsScreen`, `SampleNightScreen`, `PlanBuildingView`, `PlanReadyView`, `PaywallScreen`.)
2. **Morning:** open Home (or widget/complication/Siri) → last night, recovery, insight; background Health delivery refreshes widgets.
3. **Evening:** Home evening mode → bedtime → Tonight → alarm → wind-down (Live Activity) → breathing/meditation/sounds/reflect.
4. **Question:** Coach tab → pick or type → answer from the person's numbers, medical/crisis questions get fixed replies.
5. **Upgrade:** locked item, widget link `noctis://premium`, Settings → paywall → StoreKit purchase / restore / manage.
6. **Data control:** Settings → Data management → export, delete a category, delete all (restarts into onboarding), delete account.
7. **Reviewer with no Health data:** empty/learning states and the labelled Sample night only (see section 22).

### 2.3 Findings

**JR-01 · Info · Blocks: No · Confirmed.** `POST_LAUNCH.md` lists features that exist in code but are intentionally unreachable (remote Coach model, `RemoteModelProvider`, `ComplicationGallery`, mock backends). They are inert in Release (C2) but remain compiled in as source. File: `CoachKit/RemoteModelProvider.swift:4`. Impact: none today; review confusion if a reviewer reads strings. Recommendation: none required; consider excluding unreachable code from the shipped target after launch.

**JR-02 · Minor · Blocks: No · Confirmed.** In-app paywall sheets reuse onboarding's paywall: dismiss reads "Continue with the free plan" and the hero is the onboarding one (`Docs/POST_LAUNCH.md`, "The paywall sheets"). Impact: wording written for a new person shown to an existing user; no functional harm. Recommendation: context-specific dismiss text.

**JR-03 · Info · Blocks: No · Confirmed.** Name set in Profile is not used in Home's greeting (`POST_LAUNCH.md`). Impact: none (feature deferred). Recommendation: none.

---

## 3. Application Architecture & System Design

### 3.1 Shape

- **One local Swift package, 29 modules** layered: pure engines (`SleepKit`, `RecoveryKit`, `InsightsKit`, `SleepAnalysisKit`, `ReviewKit`, `NightKit`, `CoachKit`, `BreathingKit`, `SoundKit`, `JournalKit`), `HealthProviding` (HealthKit seam + mock), `NoctisCore` (models, stores, store/entitlements, notifications, widget publisher, deletion, privacy inventory), `DesignSystem`/`NoctisText`, feature modules (`HomeFeature` ... `ProfileFeature`), and `AppRoot` (composition). Extensions link only small kits (`NoctisWidgetKit`, `AlarmShared`, `NoctisWatchKit`).
- **Isolation (`Package.swift:3-12`).** Feature modules use `defaultIsolation(MainActor.self)`; engine modules are nonisolated by default so work runs on a repository actor off the main thread (R20). `ExistentialAny` enabled.
- **Data:** SwiftData for profile/alarm/wind-down (`NoctisSchemaV1`), separate stores for Journal and Coach history, JSON files for insights/reviews/snapshot. Widgets read one JSON snapshot in the App Group; Watch gets the same summary via WatchConnectivity; no iCloud.
- **Entry:** `App/NoctisApp.swift:12` builds `AppContainer()` in `init`, so background wakes (Health delivery, controls) have the app's host. `AppContainer` wires ~everything (940 lines).
- **Compile-time boundaries are enforced by tests** (inventory, privacy, "nothing unbuilt is reachable", Journal dependency checks) rather than by the build graph alone.

### 3.2 Findings

**ARCH-01 · Minor · Blocks: No · Confirmed.** `AppContainer.swift` is 940 lines and `DataWiring.swift` 333 lines: one composition root constructs and wires every store, service and view model. Evidence: file lengths (C6); `AppContainer.swift:550` wires Data management for every inventory category. Impact: onboarding cost, change blast radius, slower cold-launch work concentrated in one initializer (see PERF-02). Recommendation: after launch, split into per-domain composition functions; no change before release.

**ARCH-02 · Minor · Blocks: No · Strong evidence.** 37 `@unchecked Sendable` or `nonisolated(unsafe)` uses (grep), concentrated in `SoundKit` (audio taps, voice bank) and Watch receivers (`Watch/App/WatchSnapshotReceiver.swift:9`, `Watch/App/WatchBreathing.swift:16`). Several have a doc comment explaining the lock. Impact: data-race safety rests on review, not the compiler, in the audio/real-time paths; TSan on the UI suite reported clean (QA-049, reported). Recommendation: keep a short written justification per type; re-run TSan on a device build before release.

**ARCH-03 · Info · Blocks: No · Confirmed.** `QACatalog` is declared as a package library (`Package.swift` products list) and linked by `NoctisUITests` only (`project.yml:304`). Release binaries show no QACatalog or mock names (C2). Impact: none. Recommendation: none.

**ARCH-04 · Minor · Blocks: No · Confirmed.** Two parallel card/scaffold families remain (onboarding's fixed light palette versus adaptive main-app tokens) and five string catalogs instead of one (`CLEANUP_REPORT.md`; catalogs found: App, DesignSystem, NoctisText, CoachKit, NightFeature, ProfileFeature). Impact: duplicated fixes (the accessibility OPEN rows often hit shared components), harder localization. Recommendation: converge after launch.

**ARCH-05 · Info · Blocks: No · Confirmed.** Last-resort crash points exist by design: `NoctisStore.swift:42` `try!` on an in-memory container (cannot fail unless the schema is invalid), `CoachTokens.swift:7` `try!` on a constant regex, `DataInventory.swift:329` `preconditionFailure` on an unknown category id, `HomePreviews.swift:41` `fatalError` in a preview. Impact: none expected; one stale ledger row (QA-003, `fatalError` on store open) is FIXED. Recommendation: none.

**ARCH-06 · Info · Blocks: No · Confirmed.** Stale comment in `project.yml:230`: "The target is empty for now" on `NOCTISWatchWidgets`, which contains complications (`Watch/Widgets/NOCTISWatchWidgets.swift`). Recommendation: update the comment after launch (documentation only).

---

## 4. Code Quality & Maintainability

### 4.1 Measures

| Measure | Value | Source |
| --- | --- | --- |
| Compiler warnings, Release | **0** | C1, verified |
| `TODO` / `FIXME` / `HACK` in shipped code | 0 | grep |
| Force operations in shipped code | 4 (ARCH-05) | grep |
| `try?` swallow sites | many (not counted; not all reviewed) | not verified |
| `#if DEBUG` blocks | 112 in 44 files | C2 |
| Legacy API markers (`DispatchQueue`, `ObservableObject`, `@Published`, `NavigationView`) | 9 | grep |
| Files over 400 lines | 45 after formatting (project count); largest `HomeScreen.swift` 1,052, `PaywallScreen.swift` 1,048, `AppContainer.swift` 940 | wc; `CLEANUP_REPORT.md` |
| SwiftLint default rules | 4,043 (3,229 `line_length`, 313 `identifier_name` errors, 43 `file_length`, 26 `cyclomatic_complexity`, 22 `function_body_length`) | C5; **no project config; indicative only** |
| Test code vs shipped code | about 44.9k vs 76.1k lines; 2,643 `@Test` + 219 XCTest | counts |
| Written rules | `APP_RULES.md` (396 lines, R1-R69), `QA_LEDGER.md`, privacy inventory tests | docs |

### 4.2 Findings

**CQ-01 · Info · Blocks: No · Confirmed.** SwiftLint reports 4,043 items with default rules because the project has no `.swiftlint.yml` and uses `swift-format` (`.swift-format`). The count is dominated by `line_length` (the codebase's lines are long by its own formatter setting). Impact: none; do not read it as 4,043 defects. Recommendation: either add a lint config that matches the formatter or do not run SwiftLint in CI.

**CQ-02 · Minor · Blocks: No · Confirmed.** 45 shipped files exceed 400 lines; the big ones are per-screen view collections (`HomeScreen.swift`, `PaywallScreen.swift`, `HomeBlockViews.swift`). Many source-text tests read files by name, so splitting is costly (`CLEANUP_REPORT.md`). Impact: review and merge friction. Recommendation: post-launch.

**CQ-03 · Minor · Blocks: No · Strong evidence.** Source-text tests (tests that read Swift files and assert on text) couple the test suite to file names and layout (`CLEANUP_REPORT.md`). Impact: refactors break tests that do not test behaviour; they also give strong guarantees (privacy, DEBUG isolation). Recommendation: keep for privacy invariants; avoid adding more for style.

**CQ-04 · Minor · Blocks: No · Confirmed (reported).** Timing-sensitive tests fail intermittently under machine load (QA-028; three different tests failed in two loaded runs, all passed alone). `NOCTIS-Store` was intermittent before QA-188. Impact: a future CI would be flaky; a real failure could be dismissed as flake. Recommendation: before CI exists, quarantine or deflake the timing tests; run the suite on a quiet machine for any release gate.

**CQ-05 · Info · Blocks: No · Confirmed.** 112 `#if DEBUG` blocks implement launch flags (`-mockScenario`, `-forceTier`, ...). They are verified absent from Release by C2, but each is a maintenance cost and a mutation risk. Recommendation: keep the symbol check as a release gate (it already passes); run it on the signed archive too.

**CQ-06 · Minor · Blocks: No · Confirmed (reproduced here).** Source-scanning tests break when the checkout path contains a symlink. They derive the repo root from `#filePath` (`Tests/NoctisKitTests/PreferencesTests.swift:593`) but enumerate files with `FileManager`, which returns resolved paths; stripping the root prefix then leaves garbage such as `/privateProfileFeature/PrivacyViews.swift`. In this audit's first run (snapshot under `/tmp`, a symlink to `/private/tmp`) about two dozen privacy/Journal/defaults guard tests failed for that reason (for example `noScreenWritesAPrivacyClaimOfItsOwn`, `theJournalsOwnFilesNeverLogCountSendOrShare`, `onlyTheWrapperNamesTheSharedUserDefaults`); the same tests all passed when the identical tree was run from a canonical path (C4b). Impact: the privacy guard tests are the project's strongest invariant checks and silently depend on where the repo lives (a CI runner under a symlinked workspace would show false failures). Recommendation: resolve both sides with `resolvingSymlinksInPath()`.

---

## 5. Authentication, Account Management & Security

### 5.1 What exists

Optional Sign in with Apple only: the Apple user identifier is stored in the iPhone's Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable: `AccountStore.swift:120-146`); the app asks Apple at launch whether it is still valid (`AccountStore.refresh`). No feature depends on being signed in. No passwords, tokens, API keys or server session exist. Account deletion = "Delete account and data" (Keychain item + all local data). Authorization surfaces: Health read-only, notifications, AlarmKit.

### 5.2 Findings (MASVS-style)

**SEC-01 · Minor · Blocks: No · Potential risk.** Keychain item survives uninstall (`AccountStore.swift:120`); no first-run reset found in `AppRoot`. A reinstalled app can start "signed in" with an empty profile until `refresh()` asks Apple. (First raised as X-11.) Impact: confusing state, no data exposure. Recommendation: record a first-launch marker in `UserDefaults` and clear the Keychain item when the marker is absent.

**SEC-02 · Minor · Blocks: No · Confirmed.** `noctis://premium` opens the paywall sheet from any app or web page (`WidgetURLRouter.swift:17-18`), but the Info.plist comment and R44 text say the scheme accepts only the five screen links (`App/Info.plist:10-11`, `WidgetURLRouter.swift:3-8`). The router comment itself mentions the premium link, so the plist comment is stale. Impact: a web page can open a read-only sheet; no state change, no purchase. Recommendation: fix the comment; no code risk.

**SEC-03 · Minor · Blocks: No · Confirmed.** "Export my data" writes JSON, including Journal text, to the temporary folder with `.atomic` only (`NoctisCore/DataManager.swift:183-186`), i.e. default file protection (complete-until-first-authentication), unlike the Journal and Coach stores (`.complete`). The file is removed on leaving Data management and at next launch (`discardExport()`, `DataManager.swift:113`, `191-193`). Impact: the most sensitive copy of the person's data is briefly stored at a weaker class; an app kill leaves it until next start. Recommendation: write with `.completeFileProtection`.

**SEC-04 · Info · Blocks: No · Confirmed.** Widget and Sleep-sounds files in the App Group use `afterFirstUnlock` on purpose (Lock Screen widgets must read them). They hold derived numbers (recovery, sleep, plan flag), never raw Health samples (`PRIVACY_REPORT.md` section 2). Impact: readable by any process with the App Group while unlocked-once; acceptable for this threat model. Recommendation: none.

**SEC-05 · Minor · Blocks: Decide · Confirmed.** No privacy overlay when the app moves to the background: `scenePhase` is observed only for clocks and audio (`RootView.swift:119`, Home, Night screens); no blur or redaction exists anywhere in `Sources` (grep). iOS stores the app-switcher snapshot, which can show a recovery score or Journal text (`PRIVACY_REPORT.md` section 6, item 6). Impact: a sleep/health/journal app showing its content in the switcher; an owner decision, but a standard expectation for health apps. Recommendation: redact content when `scenePhase != .active`.

**SEC-06 · Info · Blocks: No · Strong evidence.** Local entitlement state (`EntitlementCache` one word, snapshot plan flag) can be forged on a jailbroken device (P-01, P-02). No server resource is protected, so the impact is limited to local Premium UI. Recommendation: none required; optional re-verify with `AppTransaction` later.

**SEC-07 · Info · Not verified.** No MASTG dynamic test was done (jailbreak, debugger, binary patch, runtime hooking). **Blocks: No.** Recommendation: optional pre-launch pass if the owner wants a security attestation.

**SEC-08 · Info · Confirmed.** Entitlements are minimal (`Config/Noctis.entitlements`): Sign in with Apple, HealthKit with background delivery, App Group; no network, iCloud, push, keychain-sharing or associated-domains entitlement. Impact: small attack surface. Recommendation: none.

---

## 6. Privacy, Permissions & Data Collection

Detailed data-flow and declaration review is in section 15/16 and the project's `PRIVACY_REPORT.md`; this section records what was verified in code and adds findings not raised in 12-25.

### 6.1 Permission and collection inventory (verified in plist, entitlements, code)

| Surface | Declared | Used for | Verified |
| --- | --- | --- | --- |
| HealthKit read: sleep, heart rate, resting HR, HRV, respiratory rate | `NSHealthShareUsageDescription` (`project.yml:114`), no write key | Recovery, Sleep, Insights, widgets | Built plist (C3) shows the string; no `toShare` |
| HealthKit background delivery | entitlement | Widget refresh | `HealthKitProvider.swift` background plan |
| Notifications | runtime request | Reminders, wind-down, weekly review | `NotificationScheduler.swift:150-152` |
| AlarmKit | `NSAlarmKitUsageDescription` (`App/Info.plist`) | Wake alarm | C3 |
| Audio background mode | `UIBackgroundModes: audio` (`App/Info.plist:23`) | Sleep sounds | plist |
| Sign in with Apple | entitlement | optional local id | `AccountStore` |
| Camera, microphone, location, contacts, photos, tracking | none | n/a | plist grep |
| Data collected by the developer | none | n/a | no network code (section 12) |

### 6.2 Findings

**PRIV-01 · Major · Blocks: Decide · Strong evidence (runtime Not verified).** Onboarding asks Health for 3 kinds (`OnboardingFeature/HealthScreen.swift:10`, request at `:165`), but `authorizationStatus()` reports "authorized" only when HealthKit says no request is needed for **all five** (`HealthProviding/HealthKitProvider.swift:24-28`). After onboarding alone the status is `notDetermined`, and Home/Sleep/Recovery/Insights load data only when it is `authorized` (`PRIVACY_REPORT.md` section 6, item 2). Impact: a person who has just granted access may see "Connect Apple Health" and a second Apple permission sheet; for a reviewer without data this could read as a broken permission flow. Recommendation: request all five kinds in onboarding, or make the status check match the kinds actually requested. (Same root as X-26.)

**PRIV-02 · Minor · Blocks: Decide · Confirmed.** Diagnostic analytics events go to the unified log with `privacy: .public` (`NoctisCore/Analytics/NoctisAnalytics.swift:21-25`). Parameters are plan ids and flags only. Impact: readable in a shared diagnostics report; policy should say so (X-12). Recommendation: either `.private` or list "diagnostic log" in the policy.

**PRIV-03 · Minor · Blocks: No · Confirmed.** `Delete all NOCTIS data` and per-category deletes remove rows but SQLite free pages can keep text (X-15; `PRIVACY_REPORT.md` section 6, item 5). Impact: "deleted" wording is stronger than the on-disk fact for single-category deletes. Recommendation: vacuum after category deletes or reword.

**PRIV-04 · Info · Blocks: No · Confirmed.** Privacy statements shown in the app come from `PrivacyStatements`, which only returns a sentence while the data inventory backs it, and tests (`DataInventoryTests`, `PrivacyManifestTests`) fail when a store, key, file, network API or required-reason API appears without an inventory entry. This is a strong guard. Recommendation: none; keep the tests as a release gate.

**PRIV-05 · Info · Not verified.** Whether the policy, manifest, App Store Connect answers and in-app Privacy Center agree word for word was not tested; only the repository drafts exist (L-05). **Blocks: Yes (L-05).**

---

## 7. UI/UX & Accessibility

### 7.1 What was measured in code

| Support | Count in shipped `Sources` | Note |
| --- | --- | --- |
| `accessibilityLabel` / `Hint` / `Hidden` / `Element` / `Value` | 331 / 80 / 126 / 169 / 28 | broad VoiceOver work |
| `accessibilityIdentifier` | 364 | for UI tests |
| `accessibilityReduceMotion` reads | 107 | motion is gated |
| `dynamicTypeSize` / `ScaledMetric` / `relativeTo:` | 130 / 17 / 711 | custom scaled type system (`NoctisTypography.swift`) |
| `accessibilityReduceTransparency`, `...DifferentiateWithoutColor`, `legibilityWeight` | **only in `AppRoot/EnvironmentProbe.swift` (a QA probe)** | see UX-03 |
| `colorSchemeContrast` | 8 | increase-contrast handling exists |
| Fixed-size fonts (`.system(size:`) | 102 | most pass through a scaling helper (`NoctisScaledType.swift:41`, `NoctisTypography.swift:163,178`); some do not (e.g. `OnboardingFeature/WelcomeBands.swift:63` fixed 12 pt) |
| Orientation | portrait only (`UISupportedInterfaceOrientations`) | iPhone only |

Reported QA: tier-1 617 combinations produced and viewed (SE, 17 Pro, 17 Pro Max; light, dark, AX3, AX5 on SE and 17 Pro); 54 NOTE + 49 FINDING rows in the tier-1 sheets; ledger has 18 OPEN minors, most layout fixes "in source, not re-photographed". **Not re-viewed in this audit; no UI test was run here.**

### 7.2 Findings

**UX-01 · Minor · Blocks: No · Confirmed (reported).** 18 OPEN minor ledger rows are layout/accessibility problems whose fixes exist in source but were never re-photographed, so their status is "unverified as an image": QA-081, 082, 083, 084, 086, 087, 089, 090, 092, 093 to 098, 115, 116 and others (`QA_LEDGER.md` lines 195-230). Examples: chevrons not mirrored in RTL (not a v1 language), Insights chip row clipping, Notifications row breaking mid-word at large sizes, delete sheet taking over half the screen at AX3. Impact: a few screens may still clip at the largest text sizes. Recommendation: re-run the tier-1 AX3/AX5 matrix on the final build, view, and close the rows.

**UX-02 · Minor · Blocks: Decide · Confirmed (reported).** Tier C accessibility settings (Reduce Motion, Increase Contrast, Bold Text, Button Shapes, On/Off Labels, Reduce Transparency, Differentiate Without Color, Smart Invert) were **not run on the final build** (`QA_LEDGER.md` 3.4); the VoiceOver traversal test is written but not run (3.7). Impact: unknown behaviour for people who depend on those settings. Recommendation: run the existing test classes and do a real VoiceOver pass on device (see `DEVICE_TEST_CHECKLIST.md`).

**UX-03 · Major · Blocks: Decide · Confirmed (code), impact Not verified.** The shipped app does not read Reduce Transparency, Differentiate Without Color or Bold Text: the three environment values appear only in `AppRoot/EnvironmentProbe.swift:11-14` (a QA probe). The app uses translucent materials and colour-coded states (Recovery bands, insight tones). Impact: with Reduce Transparency or Differentiate Without Color on, content that depends on blur or colour alone may be hard to read or distinguish; an accessibility audit (Apple's accessibility nutrition label, if the owner claims support) would flag it. Recommendation: read those environment values in the shared design-system components and provide opaque and shape/label alternatives; at minimum do not claim support in App Store accessibility labels until tested.

**UX-04 · Minor · Blocks: No · Confirmed.** iOS 27-only gestures: Insight swipe actions and the Home swipe container are `#available(iOS 27, *)` (`HomeFeature/HomeBlockViews.swift:571`, `HomeView.swift:369`); on iOS 26 only long-press remains. These are the only two availability branches in 411 files, so the iOS 26.1 path of those two views has **never been run** (QA ran on iOS 27). Impact: discoverability on 26.x; possible untested layout. Recommendation: run Home on an iOS 26.1 runtime before declaring the minimum.

**UX-05 · Minor · Blocks: No · Confirmed.** Portrait-only, iPhone-only; the app declares `TARGETED_DEVICE_FAMILY: 1` and disables Mac and Vision "Designed for iPhone" (`project.yml:23-26, 101`). On iPad the App Store will not offer the app. Impact: reduced audience; consistent with the listing. Recommendation: none; confirm the owner wants no iPad/Mac availability.

**UX-06 · Info · Blocks: No · Confirmed.** Medical notice appears on the welcome screen, paywall, About, Watch and Terms (QA-142). Impact: positive. Recommendation: keep.

---

## 8. Performance & Application Stability

### 8.1 Verified here versus reported

| Result | Source |
| --- | --- |
| Release build compiles without warnings (all five shipped targets and the package) | **Verified (C1)** |
| Package unit suite | **Verified here (C4b): 2,619 tests in 355 suites passed, 658.9 s, TEST SUCCEEDED**; the same counts the project reported. iOS 27 simulator only; not run on iOS 26.x or a device |
| 730 nights: Home 0.23 s, Sleep 0.18 s, Recovery 0.21 s, month build 0.014 s, 24 reviews 0.13 s, memory +19 MB | Reported, **simulator, Debug, mock provider** (QA-122) |
| Leaks (Tonight, ~10 laps): 46 blocks, 1,472 bytes | Reported (QA-044), simulator |
| UI suite under Thread Sanitizer: 127 of 130 passed, no race | Reported (QA-049) |
| Historic blocker QA-040: alarm row rewritten about 2,000 times a second (6.05 GB `default.store`) | Reported FIXED; regression tests exist (`AlarmConfigurationTests`, `StoreSafetyTests`, `AlarmServiceTests`) but were not run here individually |

### 8.2 Stability mechanisms found in code

Atomic file writes keeping the old file whole on failure (QA-134); unreadable databases set aside whole into `Noctis/Quarantine` and the app starts empty, never deleting (`StoreRecovery.swift`); a locked-device store is left in place and the app runs in memory; refresh tickets prevent stale entitlement answers (`EntitlementManager.swift` ticket counter); expiry timer; HealthKit observers wrapped in `AsyncStream` with cancellation.

### 8.3 Findings

**PERF-01 · Major · Blocks: Decide · Confirmed.** **No performance number exists from a physical device.** All timings are simulator, Debug, mock data (QA-122), the cold-launch budget is "to set from the first device run" (`DEVICE_TEST_CHECKLIST.md`), and Instruments memory/battery runs are device-only rows with no tick. Impact: launch time, scrolling and battery for a night-long app (audio, Live Activity, Watch sync, Health background wakes) are unknown. Recommendation: complete the device checklist's performance section on the oldest supported iPhone before submission.

**PERF-02 · Minor · Blocks: No · Strong evidence.** `AppContainer()` is built synchronously in `NoctisApp.init` (`App/NoctisApp.swift:12`) and wires every store, service and observer before the first frame, by design (background wakes need it). Impact: cold-launch cost scales with container wiring (940-line file); no budget or signpost threshold is set. Recommendation: measure on device; defer non-essential wiring if over budget.

**PERF-03 · Minor · Blocks: No · Strong evidence.** `EntitlementManager.refresh()` queries `Product.products(for:)` and subscription status on every refresh (`EntitlementClient.swift` `renewal()`); refreshes occur at launch, on transaction updates and at plan end. Impact: small network use through StoreKit, offline falls back to cached entitlements (P-04). Recommendation: none required.

**PERF-04 · Minor · Blocks: No · Potential risk.** Background Health delivery asks for hourly sleep and daily HRV/resting heart rate wakes (`HealthProviding/HealthBackgroundDelivery.swift:6-17`, applied at `HealthKitProvider.swift:201`) and the app republishes widgets and the Watch summary on each wake; Watch complication transfers have a daily budget (`NoctisSignpost.watchComplicationBudget`). Impact: battery and Watch budget behaviour is unmeasured. Recommendation: measure one real night with and without a paired Watch (checklist rows exist).

**PERF-05 · Minor · Blocks: No · Confirmed (reported).** Intermittent timing tests under load (CQ-04) mean a "pass" is only meaningful on a quiet machine. Recommendation: see CQ-04.

**PERF-06 · Info · Blocks: No · Confirmed.** Stability design is strong for storage failure (quarantine, atomic writes, in-memory fallback). No crash reporting beyond Apple's exists (section 19), so field stability will not be observable by the developer except through Organizer. **Recommendation:** retain archives and dSYMs for every shipped build (section 21).

---

## 9. Functional Completeness & QA Coverage

### 9.1 Completeness

`ROADMAP.md` is empty and `NothingUnbuiltIsReachableTests` holds it: no reachable "coming soon". `POST_LAUNCH.md` lists about 40 deferred features that are not in the app (remote Coach, iCloud sync, recorded meditations, Smart Wake, yearly review, Sinhala/Tamil, configurable widgets). Every listed feature in section 2 has an implementation in source (module present, tier row present); behaviour was not exercised by this audit.

### 9.2 QA coverage (reported, from `QA_COVERAGE.md`, `QA_REPORT.md`, `QA_LEDGER.md`)

| Layer | Evidence | State |
| --- | --- | --- |
| Unit and engine tests | 2,619 tests / 355 suites (reported at 6105f16); fuzz on 4 seeds; time-zone, region, clock and first-weekday configurations via `Config/NOCTIS.xctestplan` | Reported pass; C4 re-run here (see 1.4) |
| Purchases | `NOCTIS-Store` scheme, `SKTestSession` over the real `Noctis.storekit` | 3 of 3 reruns reported; known simulator artifacts (QA-129) |
| UI / screen matrix | Tier 1: 617 combinations, all produced and viewed; 140 of 204 iPhone screens in tier 1; 19 Watch screens tier 2 (not planned for v1) | Reported |
| Accessibility | AX3/AX5 on SE and 17 Pro; Tier C and VoiceOver traversal not run on final build | Partly |
| Privacy | inventory, manifest, no-requests walk, symbol audit | Reported pass; symbol audit reproduced here |
| Device / Watch / Sandbox / iOS 26.x | `DEVICE_TEST_CHECKLIST.md`: **no row ticked** | Not done |

### 9.3 Findings

**FUNC-01 · Major · Blocks: Yes · Confirmed.** No physical-device verification exists for any feature that depends on hardware or system services: AlarmKit ringing locked/silent, notification delivery, HealthKit background delivery, Live Activity and Dynamic Island, Control Center controls, Siri, WatchConnectivity transfer, complications, haptics, real purchase and expiry (`DEVICE_TEST_CHECKLIST.md`, `POST_LAUNCH.md` "Checks that need a real device"). Impact: the headline night features (alarm, wind-down, widgets, Watch) are the ones most likely to behave differently on hardware. A wake alarm that fails is a user-harm and review risk. Recommendation: run the full device checklist, with the alarm test first (locked, silent, Focus on, after reboot).

**FUNC-02 · Minor · Blocks: No · Confirmed (reported).** Widgets on a real Home/Lock Screen, the wind-down Live Activity, Control Center controls and notification banners were not captured in QA (QA-150: `simctl push` is refused); the widget gallery is a DEBUG simulation. Impact: real-surface layout, redaction on the locked screen and tint modes are untested. Recommendation: capture on device.

**FUNC-03 · Minor · Blocks: No · Confirmed (reported).** Several re-shoot rows remain "pending" after catalog fixes (QA-078 empty reviews list, QA-146 goal subtitle, QA-147 delete confirmations). Impact: those screens are unverified as images. Recommendation: re-run and view (ties to UX-01).

**FUNC-04 · Minor · Blocks: No · Confirmed.** Known functional gap: plan expiry while the app is not running is not seen by widgets, Watch or Siri until next launch (P-03). Impact: minor revenue leak; no safety issue. Recommendation: carry the period end date in the snapshot so surfaces lock themselves.

**FUNC-05 · Info · Blocks: No · Confirmed.** `NOCTIS-Store` and UI suites were not run in this audit (time and device-farm constraints); the previous run counts are the project's own. Recommendation: the owner or a CI job should run both on a quiet machine as a pre-submit gate.

---

## 10. iOS, Swift, SwiftUI & Framework Compatibility

### 10.1 Facts

| Item | Value | Source |
| --- | --- | --- |
| Deployment | iOS 26.1 (raised from 26.0 for the bedtime tab accessory and AlarmKit alert: QA-019), watchOS 26.0 | `project.yml:4-6, 62, 191`, `Package.swift:19`, built plist `MinimumOSVersion 26.1` |
| Built against | iphoneos27.0 SDK (`DTSDKName`), Xcode 27.0 (27A266a), Swift 6.4 | C3, `xcodebuild -version` |
| Language | Swift 6 mode, complete strict concurrency, `ExistentialAny`; package tools 6.2 | `project.yml`, `Package.swift:1,5-11` |
| Frameworks used | SwiftUI, SwiftData, HealthKit, StoreKit 2, AlarmKit, WidgetKit, App Intents, ActivityKit, WatchConnectivity, AuthenticationServices, FoundationModels, MessageUI, AVFoundation, UserNotifications, OSLog | imports found by search |
| Apple Intelligence | `SystemLanguageModel` backend for Coach, with a template fallback | `CoachKit/SystemLanguageModelBackend.swift` |
| Availability branches | 2 (`#available(iOS 27, *)`), both in Home swipe actions | `HomeBlockViews.swift:571`, `HomeView.swift:369` |
| Runtimes available to test | iOS 27.0, watchOS 27.0 only | `xcrun simctl list runtimes` |

### 10.2 Findings

**COMP-01 · Major · Blocks: Yes · Confirmed.** The app has **never run on iOS 26.1 to 26.x** (QA-020): QA used iOS 27 only. The compiler proves API availability at 26.1 (an iOS 27 API without a guard would not compile against deployment 26.1), but not runtime behaviour, layout or entitlement/AlarmKit/FoundationModels differences. Impact: the stated minimum version is a promise nobody tested; all iOS 26 users would be first testers. Recommendation: install an iOS 26.1 simulator/device and run at least onboarding, Home, alarm, paywall, widgets, Watch pairing, and the `DEVICE_TEST_CHECKLIST.md`; or raise the minimum to what was tested.

**COMP-02 · Minor · Blocks: Decide · Strong evidence.** Building with the iOS 27 SDK while deploying to 26.1 depends on a release (non-beta) Xcode for upload; `27A266a` was seen locally but whether it is the GA build was not verified. App Store Connect rejects binaries built with a beta Xcode/SDK. Impact: a blocked upload at the last step. Recommendation: confirm in Xcode > About and Apple's release notes that the toolchain used for the archive is a released version; archive with that.

**COMP-03 · Minor · Blocks: No · Strong evidence.** Coach quality and availability depend on Apple Intelligence hardware and region; on unsupported devices Coach falls back to the template provider (`AIService.swift`, availability mapping). The fallback behaviour was tested with fakes, not on a real device without Apple Intelligence. Impact: different Coach experience per device; review notes must describe it (L-06). Recommendation: test both paths on devices.

**COMP-04 · Info · Blocks: No · Confirmed.** Watch deployment 26.0 versus iPhone 26.1: a person on watchOS 26.0 with iOS 26.1 is supported by the pairing matrix on paper; not tested. Recommendation: include on the device matrix.

**COMP-05 · Info · Blocks: No · Confirmed.** Legacy API use is small (9 markers; no `NavigationView`/`ObservableObject` state in the new code paths); the code uses `@Observable` and Swift Testing. Recommendation: none.

---

## 11. Core Release Configuration & Initial App Store Readiness

### 11.1 Verified configuration

| Item | Value | Evidence |
| --- | --- | --- |
| Bundle IDs | `com.noctis.app`, `.widgets`, `.alarm`, `.watchkitapp`, `.watchkitapp.widgets`; App Group `group.com.noctis.app` | `project.yml`, entitlements |
| Version / build | 1.0 / 1, hand-set at `project.yml:18-19` | project.yml; built plist (C3) |
| Signing | No team; unsigned Release build passes (C1) | project.yml; C1 |
| Entitlements | Sign in with Apple, HealthKit (+ background delivery), App Group | `Config/*.entitlements` |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in iPhone and Watch targets | `project.yml` |
| Orientation / device | portrait, iPhone only; Watch family 4 | built plist |
| Icons | 1024 x 1024, no alpha: AppIcon Light, Dark, Watch | `sips` (C6) |
| Launch screen | `LaunchScreen.storyboard` | `App/` |
| Privacy manifests | 5, one per shipped target, all present in the built bundle | C3 |
| Background modes | iPhone `audio`; Watch `mindfulness` | plists |
| URL scheme | `noctis` | `App/Info.plist:12` |
| StoreKit config | `Config/Noctis.storekit` attached to the scheme, not bundled | `project.yml:94` |
| Embedded structure | one app, Watch app embedded, 3 extensions on iPhone side + 1 on Watch | C3 |

### 11.2 Findings (not repeating L-01 to L-09)

**REL-01 · Major · Blocks: Yes · Confirmed.** Signing, identifiers and capabilities are not set up: no `DEVELOPMENT_TEAM`, five bundle IDs and the App Group unregistered, HealthKit/background delivery/Sign in with Apple capabilities unprovisioned (L-03). An unsigned Release build and structure check were verified here, but a **signed archive and App Store validation have not been attempted** (QA-027). Impact: entitlement or profile problems (for example HealthKit background delivery needs the capability on the App ID) surface only at signing. Recommendation: register IDs, set the team, archive, run Validate App, record the result.

**REL-02 · Minor · Blocks: No · Confirmed.** Version and build numbers are hand-edited constants (`project.yml:18-19`), and the generated `Noctis.xcodeproj` is committed alongside `project.yml`. A second upload requires a higher `CURRENT_PROJECT_VERSION`, and a stale pbxproj would ship the old number. Recommendation: bump in `project.yml` then regenerate; check `git diff Noctis.xcodeproj` before archiving (the README already says to).

**REL-03 · Minor · Blocks: No · Confirmed.** `Noctis.storekit` contains test prices and `familyShareable: false`; the real products, prices, family sharing and intro offer must be created to match in App Store Connect (L-04, P-05, P-08). A mismatch of product IDs means the paywall shows "unavailable" (`StoreLoadState.unavailable`). Recommendation: create products with the exact IDs and test with a sandbox account before submitting.

**REL-04 · Minor · Blocks: No · Confirmed.** `UIBackgroundModes` is `audio` only; sleep sounds are synthesized and play only after the person starts one. App Review sometimes questions the audio background mode. The review notes already explain it. Recommendation: keep the explanation in the notes; be ready to show the sound playing with the screen locked.

**REL-05 · Minor · Blocks: No · Confirmed.** `App/Info.plist` comments say the scheme accepts only five links, while the router also accepts the paywall link (SEC-02). Recommendation: update the comment.

**REL-06 · Info · Blocks: No · Confirmed.** Release-vs-Debug separation is correct: Release build has 0 warnings (C1), no debug names (C2), no mock names in any of 7 binaries, `StoreKit` configuration only on the scheme. Recommendation: re-run C2 on the final signed archive.

### 11.3 Initial App Store readiness

Technical packaging is ready to archive (C1 to C3). The submission itself is **not** ready: legal pages, domain, signing, App Store Connect records, screenshots, privacy answers, device pass and iOS 26.x run are open (L-01 to L-09, REL-01, COMP-01, FUNC-01). Readiness verdict for this slice: **Ready to archive for TestFlight once the team is set; not ready to submit.**

---

## Consolidated Critical Findings (all sections 1-25)

"Blocks release" lists items that must be closed or consciously accepted before pressing Submit. Nothing was fixed.

| Rank | ID | Finding | Blocks | Confidence |
| --- | --- | --- | --- | --- |
| 1 | L-01 / L-02 | Terms, privacy and support URLs and addresses are placeholders; draft pages unpublished and contain 5 placeholders | Yes | Confirmed |
| 2 | L-03 / REL-01 | No signing team, IDs or capabilities; no signed archive or App Store validation | Yes | Confirmed |
| 3 | L-04 | No App Store Connect app, subscriptions, agreements, tax, sandbox testers | Yes | Not verified |
| 4 | FUNC-01 / L-08 | No physical-device run: alarm, notifications, background Health, widgets, Watch, Live Activity, purchase/expiry | Yes | Confirmed |
| 5 | COMP-01 | Never run on iOS 26.1 to 26.x, the stated minimum | Yes | Confirmed |
| 6 | L-05 | Owner sign-off on privacy report and App Privacy answers (support-email Option A/B) | Yes | Confirmed open |
| 7 | L-06 | Review notes say Coach uses "fixed wording"; code enables the on-device generative model by default | Yes (review risk) | Strong evidence |
| 8 | L-07 | Screenshots not usable; no Watch screenshots | Yes | Confirmed |
| 9 | L-09 | No git remote: the only copy of the source is on one Mac | Decide (high loss risk) | Confirmed |
| 10 | PRIV-01 / X-26 | Onboarding requests 3 Health kinds; status check needs 5; "Connect Apple Health" may reappear | Decide | Strong evidence |
| 11 | UX-03 | Reduce Transparency, Differentiate Without Color, Bold Text are not read by shipped code | Decide | Confirmed |
| 12 | PERF-01 | No on-device performance, memory or battery numbers | Decide | Confirmed |
| 13 | SEC-05 | No background privacy overlay for a health and journal app | Decide | Confirmed |
| 14 | COMP-02 | Toolchain used for upload must be a released Xcode (not verified) | Decide | Potential risk |
| 15 | X-22 / section 15 | Health-claim wording and keywords need legal review | Decide | Legal review |

Major but not blocking: SEC-03 (export file protection), X-10/L-09 (no CI/remote), P-03/FUNC-04 (expiry gap on widgets/Watch), X-16 (no migration stages), X-20 (no remote kill switch), X-13 (no crash reporting or dSYM retention), X-21 (trademark/domain).

---

## Missing Audit Coverage

| Area | Why it is missing | What is needed |
| --- | --- | --- |
| Test results beyond C4 | `NOCTIS-Store` scheme, UI suites, QA matrix, Instruments, Thread Sanitizer, accessibility audits were not run here | Quiet machine run, or CI; device for Instruments |
| Source review depth | A few dozen of the 411 shipped files read (not counted exactly); remaining reviewed by search or tool output only; Watch/widget view code and most of the 168 test files unread | Targeted review of alarm, notification, Health, Watch sync, and deletion paths |
| iOS 26.x behaviour | No 26.x runtime installed | iOS 26.1 simulator or device |
| Physical devices (iPhone, Apple Watch) | No access | Devices, a Health store with data |
| Apple Developer account / App Store Connect | No access | Account owner |
| Sandbox / TestFlight purchases | No access | Sandbox tester, signed build |
| Live legal site and domain | No network probing was done | Owner to publish; verify URLs |
| Legal and regulatory review | No counsel | Counsel review of health claims, privacy, consumer law |
| Dynamic security testing (MASTG) | Out of scope for read-only static audit | Optional jailbroken-device test |
| Second worktree `claude/charming-liskov-749f7b` | Different, older branch with another session's uncommitted edits | Out of scope |
| Artwork authorship and licensing | Not in the repository | Owner to confirm |

---

## Updated Overall Readiness Assessment

**Verdict: unchanged and now better supported. Ready for TestFlight (after the team is set). Not ready for App Store submission.**

| Gate | Status |
| --- | --- |
| Builds clean in Release, no debug scaffolding, structure correct | **Met (verified here)** |
| Package unit suite | **Verified here (C4b): 2,619 tests in 355 suites passed, 658.9 s, TEST SUCCEEDED**; the same counts the project reported. iOS 27 simulator only; not run on iOS 26.x or a device |
| Code and architecture quality | Good; no code defect found that blocks release |
| Privacy design | Good; documents not final; one permission-flow question (PRIV-01) |
| Accessibility | Strong effort; unverified configurations; three accessibility settings unsupported (UX-03) |
| Legal and distribution | Not met (L-01 to L-07) |
| Signing, archive, validation | Not met (REL-01) |
| Real-device and iOS 26.x verification | Not met (FUNC-01, COMP-01) |
| Operations after launch | Minimal: no monitoring, no CI, no kill switch (sections 19, 21, 24) |

Fastest path (unchanged in order, now with the new items inserted): (1) domain, legal pages, support inbox; (2) Apple team, IDs, capabilities, archive and Validate App with a released Xcode (REL-01, COMP-02); (3) device pass including iOS 26.1 and the alarm (FUNC-01, COMP-01); (4) decide PRIV-01, UX-03, SEC-05 and the Coach review-notes wording (L-06); (5) screenshots; (6) owner sign-off on privacy answers; (7) set up a git remote before any further work (L-09).

A passing build and test suite do not establish production readiness. No finding in this part was fixed.

STOP: awaiting instructions.
