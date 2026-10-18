#!/bin/zsh
# QA part 3, step 6: what the built binaries link and call. Usage: scripts/qa_symbol_audit.sh <Release-iphonesimulator folder> [out file]
# For each binary: its linked frameworks, and every undefined symbol or string matching the patterns below. The widget, alarm widget, Watch app and Watch
# widget binaries must match none of HealthKit, CloudKit, URLSession or the other networking entry points; the app itself must match no CloudKit and no
# networking one (HealthKit is read there, and only there).
set -u
products=${1:?folder}
out=${2:-/dev/stdout}
patterns='HealthKit|HKHealthStore|HKSample|HKQuery|HKObserver|CloudKit|CKContainer|CKDatabase|NSURLSession|URLSession|NSURLConnection|CFNetwork|NWConnection|NWPathMonitor|nw_connection|WKWebView|SFSafariViewController'
fail=0
{
for rel in NOCTIS.app/NOCTIS NOCTIS.app/PlugIns/NOCTISWidgets.appex/NOCTISWidgets NOCTIS.app/PlugIns/NoctisAlarmWidget.appex/NoctisAlarmWidget NOCTIS.app/Watch/NOCTISWatch.app/NOCTISWatch NOCTIS.app/Watch/NOCTISWatch.app/PlugIns/NOCTISWatchWidgets.appex/NOCTISWatchWidgets; do
  b="$products/$rel"
  echo "=== $rel"
  echo "--- linked frameworks"
  otool -L "$b" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/swift' | awk '!seen[$0]++' | sed 's/^/  /'
  echo "--- undefined symbols and strings matching: $patterns"
  # SwiftData's ModelConfiguration.CloudKitDatabase.none (the app asks for NO CloudKit database) names CloudKit in a symbol: it is the opposite of use.
  hits=$( { nm -u "$b" 2>/dev/null; strings -a "$b" 2>/dev/null; } | grep -E "$patterns" | grep -v 'CloudKitDatabase' | sort -u )
  if [ -z "$hits" ]; then echo "  (none)"; else echo "$hits" | head -40 | sed 's/^/  /'; fi
  case "$rel" in
    NOCTIS.app/NOCTIS) bad=$(echo "$hits" | grep -E 'CloudKit|CKContainer|CKDatabase|URLSession|NSURLConnection|CFNetwork|NWConnection|NWPathMonitor|WKWebView|SFSafariViewController' | head -1);;
    *) bad=$(echo "$hits" | head -1);;
  esac
  if [ -n "$bad" ]; then echo "  FAIL: $bad"; fi
done
} > "$out"
grep -q '^  FAIL' "$out" && exit 1 || exit 0
