#!/bin/zsh
# usage: qa_fresh_install.sh <simulator udid> <derived data dir of a built UI test bundle>
# The system's notification prompt appears once per install, so the two OnboardingQATests that answer it are run each on a fresh install.
udid=$1; derived=$2
cd "$(dirname "$0")/.."
for test in testNotificationsGranted testNotificationsDenied; do
  xcrun simctl uninstall "$udid" com.noctis.app 2>/dev/null
  xcodebuild test-without-building -project Noctis.xcodeproj -scheme Noctis -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" -only-testing:NoctisUITests/OnboardingQATests/$test 2>&1 | grep -E "Test Case .* (passed|failed)|skipped|error:"
done
