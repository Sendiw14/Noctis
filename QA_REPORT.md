# QA_REPORT.md

The end of QA part 3 (data correctness, purchases, notifications, lifecycle, privacy enforcement), written on 2026-10-19 over the whole QA effort in `QA_LEDGER.md`
(findings and decisions, one row each), `QA_COVERAGE.md` (every screen under every configuration, what was produced and what was looked at) and `qa/` (the
records behind them). A "pass" in this report has evidence behind it; anything that has none is listed as UNVERIFIED with the reason.

## 1. Ledger

143 rows (QA-001 to QA-143).

| Severity | FIXED | OPEN | ACCEPTED | VERIFIED | PASS | UNVERIFIED | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| blocker | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| major | 11 | 2 | 0 | 0 | 0 | 0 | 13 |
| minor | 42 | 26 | 4 | 0 | 0 | 4 | 76 |
| info | 3 | 1 | 10 | 17 | 20 | 2 | 53 |
| **Total** | 57 | 29 | 14 | 17 | 20 | 6 | 143 |

FIXED means the source was changed and a test or an image shows it. Many OPEN minors below are layout fixes that are **in the source and not yet photographed**
(the row says "UNVERIFIED as an image"): they stay OPEN until the screen is looked at again, and none is counted as a pass.

Found and fixed in this part (QA part 3):

- QA-119: a sample dated after "now" could erase last night from Home, Sleep and Recovery (found by the fuzz tests).
- QA-127: Premium outlived a plan that ended while the app was open (nothing asked the store again; StoreKit never announces an expiry).
- QA-142: "NOCTIS isn't a medical device" was on About and the Watch only; it is now also on the welcome screen and the paywall.
- QA-143: the paywall did not say the plan renews automatically; it now does.

## 2. What was run

| What | Result |
| --- | --- |
| Package unit suite (`xcodebuild test -scheme NoctisKit-Package`, from Packages/NoctisKit, `SWIFT_EMIT_LOC_STRINGS=NO`) | **2531 tests in 338 suites, all pass** (618 s), on the final tree. An earlier full run had one failure: DataInventoryNetworkTests flagged the new DEBUG-only request recorder; the test now allows a wholly `#if DEBUG` file (the Release symbol audit is the proof) and the full suite was run again. The purchase tests (NOCTIS-Store, 23) and the UI no-requests test are separate runs. |
| Cross-surface consistency (Home, Sleep Day, Recovery Today, widget, Watch pages; 10 mock scenarios) | pass (QA-117). Not covered: Siri answers, Coach template, Reviews, share cards (QA-118). |
| Engine fuzz: session, quality, recovery, bedtime engines | 1500 timelines per run on the fixed seed 20260924, and 20000 on each of the seeds 1, 777 and 424242: pass (QA-120). One bug found and fixed (QA-119). |
| Health changing under the app; 730 nights | pass (QA-121); Home refresh 0.23 s, Sleep 0.18 s, Recovery 0.21 s, Sleep Month 0.014 s, Recovery 90D 0.004 s, 24 monthly reviews 0.13 s, memory +19 MB. Simulator, debug build, **not device numbers** (QA-122). |
| Time and calendar (4 zones with daylight saving, weekday-first regions, month and leap boundaries, time-zone change, midnight rollover) | 12 tests pass (QA-123 to QA-126). |
| Purchases: `SKTestSession` over the real `Noctis.storekit` through the real StoreManager (scheme **NOCTIS-Store**, app-hosted bundle) | 23 tests (44 cases for the per-feature one): 22 pass, 1 passes with a known issue (QA-128, QA-129). |
| Notifications and lifecycle | 6 + 5 tests pass (QA-132 to QA-134); cold-launch taps for five routes viewed (QA-133). |
| Privacy enforcement | 7 unit tests pass; the UI no-requests walk passes; Release binary symbol audit exit 0 (QA-138 to QA-143). |
| Screen matrix (QA part 2) | QA_COVERAGE.md: 4084 combinations planned, 2799 produced, 2211 viewed, 928 PASS, 1006 FINDING (includes findings whose fix is in source), 277 NOTE, **1873 UNVERIFIED** (not produced, or produced and not looked at). |

Images looked at in this part (every one displayed and read): the five cold-launch notification taps (`~/qa-work/tap`, two sheets), and the welcome and paywall
screens on the SE at default size and AX3 after the notice and renewal wording were added (`~/qa-work/qamx-p6/sheet_p6b.png`). The screenshot of the StoreKit
test alert covering the app was seen and discarded (QA-137). Not viewed: the welcome and paywall on the 17 Pro and at other sizes after the change.

### StoreKitTest, HealthKit, UserNotifications and simctl: checked against the installed SDK (iOS 27.0, Xcode 27)

- **StoreKitTest**: differences from older documentation are in QA-130 (deprecated `failTransactionsEnabled`, `failureError`, `buyProduct(productIdentifier:)`; `resetToDefaultState()` also turns dialogs back on;
  a hostless SwiftPM test process gets no products, so the purchase tests live in an app-hosted bundle).
- **HealthKit**: the app reads only; real HealthKit cannot be injected on the simulator (its store is empty and the app has no write access), so the provider protocol is driven by a scripted provider (QA-121). `HKSleepSchedule` is not read by the app.
- **UserNotifications**: the app schedules `UNCalendarNotificationTrigger` reminders with fixed identifiers; the scheduling seam is tested through an in-memory centre. `xcrun simctl push` delivers a remote payload with the system's own request identifier, so it cannot reach the router's identifier switch; the routed taps were checked with the app's own `-noctisNotificationTap` and unit tests (QA-133).
- **simctl**: `simctl ui` (appearance, content size, contrast), `status_bar`, `io screenshot`, `install`, `launch` with arguments, `boot` and `bootstatus` were used as documented. A rebooted simulator was needed to clear leftover StoreKit alerts (QA-137).

## 3. UNVERIFIED, with the reason

<!-- UNVERIFIED-LIST -->
- **QA-020** (Min deployment, minor): How the app behaves on iOS 26.1 to 26.x at run time.
- **QA-027** (Build, minor): A signed archive and App Store validation.
- **QA-057** (Harness, minor): Smart Invert and Reduce Motion cannot be seen in a screenshot.
- **QA-129** (Purchases, minor): StoreKitTest artifacts the app cannot tell from the real thing:
- **QA-135** (Lifecycle, info): Not verifiable on the simulator:
- **QA-138** (Privacy, info): Backup exclusion and protection per on-disk category, read back from real files made by the real stores (home snapshot, widgets' summary, Sleep sounds status, insights, reviews, Journal, Coach history):
<!-- /UNVERIFIED-LIST -->
- **QA coverage**: 1873 screen-by-configuration combinations were not produced or not looked at (QA_COVERAGE.md says which and why); several screens fixed in source in QA part 2 were not photographed again (onboarding Health rows, the journal's Delete all at accessibility sizes, Data management's Delete verb, Sleep month's caption, Delete-all padding).
- **Welcome and paywall** on the 17 Pro and at sizes other than default and AX3 after QA-142 and QA-143.
- **Main-thread stalls** in the UI during a 730-night run: no Instruments run (the simulator cannot run the Hitches instrument); the builders were timed only.
- **The Apple Watch** on a real watch, **background delivery** of Health data, **HealthKit** with real data and permissions, the **system's** scheduling of the reminders across a clock change, a **real banner tap** on a delivered notification, **VoiceOver** speech beyond what the audits read, **Smart Invert**, **Reduce Motion** as motion.

## 4. Open minors, and why they are still open

The OPEN rows after QA part 3 (the two majors are release tasks, not code):

<!-- OPEN-LIST -->
- **QA-004** (Release, major): The Terms of Use and Privacy Policy URLs (https://noctis.app/terms, /privacy) and the support address (support@noctis.app) are placeholders.
- **QA-014** (Release, major): ROADMAP.md still lists 48 items;
- **QA-078** (Data, minor): reviews.list and reviews.list.free show 'Nothing here yet':
- **QA-081** (Localization, minor): Right-to-Left:
- **QA-082** (Layout, minor): Pseudolanguages:
- **QA-083** (Localization, minor): Right-to-Left:
- **QA-084** (Localization, info): Under DoubleLength and Bounded String every unit token is doubled or bracketed, and a bare figure is buried or cut:
- **QA-085** (Localization, minor): Right-to-Left mirrors every time axis:
- **QA-086** (Layout, minor): Right-to-Left:
- **QA-087** (Layout, minor): Insights opened on a category (Heart, Recovery, Timing, Consistency):
- **QA-089** (Layout, minor): Loading skeletons wider than the SE's content:
- **QA-090** (Layout, minor): Profile (SE):
- **QA-092** (Layout, minor): Bold Text:
- **QA-093** (Accessibility, minor): Accessibility sizes, Coach:
- **QA-094** (Accessibility, minor): Accessibility sizes, Insights, Recovery and Sleep:
- **QA-095** (Accessibility, minor): Accessibility sizes, Home evening and Tonight:
- **QA-096** (Accessibility, minor): Accessibility sizes, Night:
- **QA-097** (Accessibility, minor): Accessibility sizes, sheets and editors:
- **QA-098** (Accessibility, minor): Accessibility sizes, shared parts:
- **QA-099** (Harness, minor): Under D-DoubleLength and D-Bounded the Coach conversation does not reach the answer (the question route is chosen by label, which the pseudolanguage changes:
- **QA-101** (Accessibility, minor): Accessibility sizes (AX5), the evening bedtime accessory (a tab bar accessory, system-sized) and the compact bar on Home evening are one line and are cut with an ellipsis ('Bedtime 10:30...', 'Bedtime ...
- **QA-103** (Accessibility, minor): Onboarding at accessibility sizes:
- **QA-108** (Accessibility, minor): Sleep sounds at AX3 and AX5 on an SE:
- **QA-113** (Harness, minor): coach.history at AX3 and AX5 shows the Coach hub, not History (the route taps coach.history after going back from the answer and the history button is off screen at those sizes).
- **QA-115** (Accessibility, minor): Data management at AX3 and AX5 (SE):
- **QA-116** (Accessibility, minor): Sleep month at AX3 and AX5 (SE):
- **QA-148** (Accessibility, minor): Breathing running at AX3 on the 17 Pro:
- **QA-150** (Process, major): QA part 4 steps 7 to 9 are NOT complete:
<!-- /OPEN-LIST -->

Why they are open: **QA-004** and **QA-014** need the owner (real Terms, Privacy and support addresses; the roadmap items are unbuilt features by design). QA-016 needs the owner's
export-compliance answer. The rest are layout and localization items from QA part 2 whose fix is in source and not photographed again (QA-082 to QA-116), harness gaps (QA-099, QA-113), or owner
calls: right-to-left charts mirroring (QA-085), the evening bedtime accessory at the largest text size (QA-101), the paywall's resting blank band on the 17 Pro (QA-071), the Sleep sounds card height at the largest sizes (QA-108),
and the two duplicated formatters (QA-118).

## 5. Needs a real device or a person

1. **Purchases with a Sandbox tester**: a declined Ask to Buy, billing retry with and without a grace period, a real expiry, Restore on a second device, Family Sharing (the configuration has it off).
2. **The Apple Watch**: pairing and installing from the Watch app, the morning summary arriving overnight, complications refreshing, the Live Activity on the Watch.
3. **Health**: a real overnight sleep and the background wake, a source change (a Watch replaced), data deleted in the Health app, permission revoked in Settings while the app is running, a late Watch sync at 9 AM.
4. **Notifications**: a delivered banner tapped cold and warm for each category, the system's scheduling across a real clock change, Focus modes.
5. **Lifecycle**: Airplane mode with the whole UI walked, real Low Power Mode, a full disk, background audio with the screen locked and a call or Siri interruption, the alarm ringing with the phone locked and in Do Not Disturb, a killed wind-down with its Live Activity.
6. **Data protection**: the file protection class of each file on a locked device (the simulator reports none), an iCloud and iTunes backup restore showing what is excluded.
7. **Performance**: hitches and memory on a device (Instruments), launch time cold.
8. **Accessibility by a person**: VoiceOver and Switch Control by someone who uses them, Reduce Motion and Smart Invert looked at on the device.
9. **Language and wording**: a native reader for the right-to-left pass and the pseudolanguage findings; the copy by the owner (the welcome tagline and the Better sleep goal subtitle, QA-141).
10. **Release**: the real Terms, Privacy and support addresses on the paywall and in About; a signed archive validated by App Store Connect; the export-compliance answer.
