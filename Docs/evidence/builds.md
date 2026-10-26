# Builds, archive and bundle metadata

Toolchain: Xcode 27.0 Build version 27A266a 
Simulator runtime for tests: iOS 27.0 (iPhone 18 Pro, QA 17 Pro, QA SE, QA 17 Pro Max); watchOS 27.0

| Build | Result |
|---|---|
| Debug build-for-testing, iOS Simulator, scheme Noctis (app, Watch app, widgets, alarm widget, UI tests) | succeeded, 0 warnings |
| Release build, iOS Simulator, scheme Noctis | succeeded, 0 warnings |
| Release archive, device SDK (generic/platform=iOS), unsigned (CODE_SIGNING_ALLOWED=NO) | succeeded, 0 warnings, arm64 |

Archive contents (after the SKIP_INSTALL fix, commit 4db55a9): Products/Applications holds NOCTIS.app only. Inside it: PlugIns/NOCTISWidgets.appex, PlugIns/NoctisAlarmWidget.appex, Watch/NOCTISWatch.app (with PlugIns/NOCTISWatchWidgets.appex). Before the fix the archive also held NOCTISWatch.app at the top level (two apps: Organizer cannot Distribute App).

| Bundle | Identifier | Version (build) | Minimum OS | PrivacyInfo.xcprivacy |
|---|---|---|---|---|
| NOCTIS.app | com.noctis.app | 1.0 (1) | 26.1 | yes |
| NOCTISWatch.app | com.noctis.app.watchkitapp | 1.0 (1) | 26.0 | yes |
| NOCTISWidgets.appex | com.noctis.app.widgets | 1.0 (1) | 26.1 | yes |
| NoctisAlarmWidget.appex | com.noctis.app.alarm | 1.0 (1) | 26.1 | yes |
| NOCTISWatchWidgets.appex | com.noctis.app.watchkitapp.widgets | 1.0 (1) | 26.0 | yes |

iPhone app Info.plist: UIDeviceFamily [1] (iPhone only), UIRequiredDeviceCapabilities [arm64], portrait only, UIBackgroundModes [audio], NSHealthShareUsageDescription and NSAlarmKitUsageDescription present, ITSAppUsesNonExemptEncryption false, NSSupportsLiveActivities true. No NSHealthUpdateUsageDescription (Health is read only).

NOT DONE: Validate App and upload need the owner's signing identity and an App Store Connect record (OWNER).
