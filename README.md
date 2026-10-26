# NOCTIS

A sleep and recovery app for iPhone and Apple Watch. It reads sleep, heart rate, resting heart rate, heart rate variability and respiratory rate from Apple Health (read only), works out last night, a recovery score and a bedtime for tonight, and keeps everything on the device. No account is required. Sign in with Apple is optional and local. There are no third-party SDKs and no advertising, and no analytics service: the few product events (paywall viewed, plan selected) go only to the system log on the device.

| | |
|---|---|
| Platforms | iOS 26.1+ (iPhone, portrait), watchOS 26.0+ |
| Toolchain | Xcode 27, Swift 6 language mode with complete strict concurrency |
| Version | 1.0 (1) |
| Targets | iPhone app, Watch app, Home Screen and Lock Screen widgets with controls and a Live Activity, alarm widget extension, Watch complications |
| Dependencies | none (Apple frameworks only) |

## Build and run

`project.yml` is the source of truth for the Xcode project. The generated `Noctis.xcodeproj` is committed so the project opens by double-click; regenerate it after changing `project.yml`:

```bash
brew install xcodegen
xcodegen generate
```

Then open `Noctis.xcodeproj`, pick the **Noctis** scheme and an iPhone simulator, and run. After regenerating, check `git diff Noctis.xcodeproj/xcshareddata`: Xcode rewrites `BuildableName` in the shared schemes, so keep the committed schemes and only patch paths in them.

No signing team is set in the repository. To run on a device or archive, set your team on every target in Xcode (Signing & Capabilities) and register the bundle IDs and the App Group below.

| Target | Bundle ID |
|---|---|
| NOCTIS (iPhone) | `com.noctis.app` |
| Widgets, controls, Live Activity | `com.noctis.app.widgets` |
| Alarm widget extension | `com.noctis.app.alarm` |
| Watch app | `com.noctis.app.watchkitapp` |
| Watch complications | `com.noctis.app.watchkitapp.widgets` |
| App Group | `group.com.noctis.app` |

Capabilities in use: HealthKit (read only, with background delivery), Sign in with Apple, App Groups, AlarmKit (usage description only), Live Activities. Subscriptions are `com.noctis.app.premium.yearly` and `com.noctis.app.premium.monthly`.

## Folder layout

```
project.yml            Xcode project definition (source of truth)
Config/                entitlements, StoreKit test configuration, unit test plan
App/                   iPhone app target: entry point, shortcuts, assets, Info.plist
Watch/App/             Apple Watch app
Watch/Widgets/         Watch complications
Widgets/Home/          widgets, controls, wind-down Live Activity
Widgets/Alarm/         alarm countdown widget extension
Packages/NoctisKit/    all feature and engine code, split into Swift modules (below)
Tests/UITests/         UI tests, screen matrix and accessibility audits
Tests/StoreTests/      purchase tests against StoreKit's test server
Docs/                  rules, QA ledger and reports, privacy report, roadmap
scripts/               QA matrix runner, coverage and release checks (see Docs/QA_REPORT.md)
```

## Architecture

All app code lives in `Packages/NoctisKit` as small modules, so a widget or the Watch can link only what it needs.

- **Engines** (nonisolated, pure, unit-tested): `SleepKit`, `SleepAnalysisKit`, `RecoveryKit`, `InsightsKit`, `NightKit` (bedtime recommendation, alarm state machine), `ReviewKit`, `PremiumKit` (the one feature table), `BreathingKit`, `SoundKit`, `CoachKit`.
- **Data**: `NoctisCore` (models, SwiftData stores, repositories, the data inventory), `HealthProviding` (the HealthKit provider and a seeded mock for tests).
- **Features** (SwiftUI): `OnboardingFeature`, `HomeFeature`, `SleepFeature`, `RecoveryFeature`, `InsightsFeature`, `CoachFeature`, `NightFeature`, `ProfileFeature`; `DesignSystem` holds the tokens and shared components; `AppRoot` wires everything together.
- **Shared with extensions**: `NoctisWidgetKit`, `NoctisWatchKit`, `NoctisIntentKit`, `AlarmShared`. They depend on nothing that reads Health, SwiftData or Coach.

Rules that hold across the code (details in `Docs/APP_RULES.md`):

- Views only read a view model's snapshot. No HealthKit calls, date math or scoring in views (R20).
- Every number on screen comes from an engine with a unit test, and missing data shows a stated empty state, never a placeholder (R18).
- Engines return values, never sentences with numbers in them. Words are written in the screen builders.
- Debug launch flags, mock data and QA scaffolding exist only inside `#if DEBUG`. `scripts/release_symbol_check.py` proves a Release build contains none of it.

## Tests

```bash
# Engines, view models, privacy and source-hygiene tests (run from Packages/NoctisKit)
cd Packages/NoctisKit
xcodebuild test -scheme NoctisKit-Package -destination 'platform=iOS Simulator,name=<an iPhone>' SWIFT_EMIT_LOC_STRINGS=NO

# The same unit suite under four time zone / region / clock configurations
xcodebuild test -project Noctis.xcodeproj -scheme NOCTIS-Unit -testPlan NOCTIS -destination '...'

# Purchases against StoreKit's test server (app-hosted)
xcodebuild test -project Noctis.xcodeproj -scheme NOCTIS-Store -destination '...'

# Release build contains no Debug scaffolding
xcodebuild build -project Noctis.xcodeproj -scheme Noctis -configuration Release -destination '...' -derivedDataPath /tmp/dd
python3 scripts/release_symbol_check.py /tmp/dd/Build/Products/Release-iphonesimulator
```

The screen matrix (every screen under light/dark, text sizes and accessibility settings) is driven by `scripts/qa_matrix.py` and `scripts/qa_configs.py`; see `Docs/QA_COVERAGE.md`. Build for testing first (`xcodebuild build-for-testing ...`), because the runner uses `test-without-building`.

## Documents

| Document | What it is |
|---|---|
| `Docs/RELEASE_READINESS.md` | The release audit, item by item, with the verdict and the blockers |
| `Docs/CLEANUP_REPORT.md` | What the final cleanup removed and moved, with before and after numbers |
| `Docs/APP_RULES.md`, `Docs/ONBOARDING_RULES.md` | The design and engineering rules every screen is checked against |
| `Docs/QA_LEDGER.md`, `Docs/QA_REPORT.md`, `Docs/QA_COVERAGE.md` | Findings, decisions and what was photographed |
| `Docs/PRIVACY_REPORT.md` | What data the app handles, where it lives and what leaves the device |
| `Docs/ROADMAP.md`, `Docs/POST_LAUNCH.md` | Unbuilt reachable features (none) and what is deferred |
