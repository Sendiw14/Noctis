#!/bin/zsh
# QA part 5: the iPhone's own widget snapshots, one per mock scenario, for the Watch and the widget gallery (`-phoneFixtures <folder>`), so they show the
# same night as Home. Needs a booted simulator with the NOCTIS Debug build installed: scripts/qa_phone_fixtures.sh <udid> <folder>
udid=${1:?udid}; out=${2:?folder}; mkdir -p $out
group=$(xcrun simctl get_app_container $udid com.noctis.app groups | awk '{print $2}')
for s in full sleepOnly learning empty stale gap; do
  rm -f $group/WidgetSnapshot.json
  xcrun simctl terminate $udid com.noctis.app >/dev/null 2>&1
  xcrun simctl launch $udid com.noctis.app -useMockHealth -mockScenario $s -noctisSkipOnboarding -homeMode day -forceTier premium >/dev/null
  for i in $(seq 1 25); do
    sleep 1
    [ -s $group/WidgetSnapshot.json ] && python3 -c "import json,sys;sys.exit(0 if json.load(open('$group/WidgetSnapshot.json')).get('t')=='premium' else 1)" && break
  done
  sleep 2; cp $group/WidgetSnapshot.json $out/$s.json && echo "$s written"
done
