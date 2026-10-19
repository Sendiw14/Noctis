# QA coverage

Written by `scripts/qa_tier1.py` on 2026-10-19 from `qa/tier1/` (the plan, what the harness produced, and which contact sheets were looked at). The earlier coverage tables, made before the final
build, are kept in `qa/coverage/` as history; they are not the v1 record.

## What counts

- **Tier 1** is what v1 ships and is judged on: the screens and configurations below. Every tier-1 combination must be **produced** on the final build (a top picture, and a
  bottom picture for a page that scrolls) and **viewed** (a contact sheet at a size where its text can be read, in `qa/tier1/viewed.tsv`). One that is not is UNVERIFIED, with the reason,
  and is never counted as a pass.
- **Tier 2, not planned for v1** is everything else: the other states of each screen (learning, empty, no permission, gap, stale, loading, error) beyond the ones named,
  the other accessibility settings (Bold Text, Reduce Motion, Increase Contrast, Differentiate Without Color, Button Shapes, On/Off Labels, Reduce Transparency, Smart Invert), the pseudolanguages beyond
  the two below, right-to-left, the other locales and languages, AX5 outside Settings, Privacy Center, Data management and the paywall, and the Apple Watch matrix. They were photographed in earlier
  QA parts; they are **not** a pass and not planned for v1.
- v1 ships English only (no right-to-left language is in the app: `ShippedLanguagesTests`).

## Tier 1 plan

| Device | Configuration | Screens planned |
| --- | --- | --- |
| QA17ProMax | A-dark | 12 |
| QA17ProMax | A-light | 12 |
| QA17Pro | A-dark | 60 |
| QA17Pro | A-light | 76 |
| QA17Pro | B-AX3-light | 107 |
| QA17Pro | B-AX5-light | 104 |
| QASE | A-dark | 60 |
| QASE | A-light | 76 |
| QASE | B-AX3-light | 107 |
| QASE | B-AX5-light | 104 |
| QASE | C-BoldText | 1 |
| QASE | D-Bounded | 20 |
| QASE | D-DoubleLength | 20 |

Screens: Welcome and every onboarding step, the paywall (loaded, loading, unavailable, compare), Home (day, evening), Sleep (day, week, month), Recovery (today, 7D, 30D, 90D, each factor),
Insights (all, an insight), Coach (hub, an answer), Wind-down (every state), the Alarm, Reviews (the list, the weekly and monthly covers), Profile, Settings, the Privacy Center, Data management and
each delete confirmation. Added so every QA part 4 re-photograph row (QA_LEDGER.md) is looked at in the configuration it names: Coach, Recovery, Insights, Sleep, Home, Night, Privacy, Profile,
Settings, Onboarding and the paywall at AX3 and AX5 on the 17 Pro and the SE; Bold Text on Recovery; DoubleLength and Bounded String on Home and Profile; Reviews and the loading skeletons.

## Totals

| Planned | Produced | Viewed | PASS | NOTE | FINDING | UNVERIFIED |
| --- | --- | --- | --- | --- | --- | --- |
| 759 | 731 | 530 | 459 | 8 | 59 | 233 |

140 of the 204 iPhone screens in the catalog are in tier 1; the other 64 (and the 19 Apple Watch screens) are tier 2.

## UNVERIFIED (tier 1)

- not produced: QA17Pro A-dark: settings.data-management, settings.privacy-center
- not produced: QA17Pro A-light: settings.privacy-center
- not produced: QA17Pro B-AX5-light: night.breathing.running
- not produced: QASE A-dark: settings.data-management, settings.privacy-center
- not produced: QASE A-light: settings.privacy-center
- not produced: QASE B-AX3-light: night.breathing.running
- not produced: QASE B-AX5-light: night.breathing.running, settings.privacy-center
- not produced: QASE D-Bounded: home.day.empty, home.day.error, home.day.full, home.day.gap, home.day.learning, home.day.loading, home.day.noPermission, home.day.sleepOnly, home.day.stale, home.evening.empty, home.evening.error, home.evening.full, home.evening.gap, home.evening.learning, home.evening.loading, home.evening.noPermission, home.evening.sleepOnly, home.evening.stale
- produced, not viewed: QA17Pro A-dark: privacy.delete.cache, privacy.delete.coach, privacy.delete.insights, privacy.delete.journal, privacy.delete.preferences, privacy.delete.setAside, privacy.delete.windDown
- produced, not viewed: QA17Pro A-light: privacy.delete.cache, privacy.delete.coach, privacy.delete.insights, privacy.delete.preferences, privacy.delete.setAside, privacy.delete.windDown, settings.data-management
- produced, not viewed: QA17Pro B-AX5-light: night.sounds.silent, night.sounds.timer, night.tonight, night.tonight.free, night.windDown.finished, night.windDown.prestart, night.windDown.reduced, night.windDown.running30, night.windDown.running90, onboarding.health, onboarding.notifications, onboarding.paywall, onboarding.plan, onboarding.rhythm, onboarding.sample, onboarding.welcome, premium.paywall.coachQuestions, premium.paywall.sleepMonth, premium.paywall.unavailable, premium.paywall.weeklyReview, premium.paywall.windDown, privacy.delete.reviews, profile.editor.need, profile.editor.wake, profile.screen, profile.screen.learning, recovery.30d.full, recovery.7d.full, recovery.90d.full, recovery.factor.hrv, recovery.factor.restingHeartRate, recovery.factor.sleepConsistency, recovery.factor.sleepDuration, recovery.today.full, reviews.list.free, settings.about, settings.appearance, settings.apple-watch, settings.notifications, settings.notifications.denied, settings.subscription.free, settings.wind-down, sleep.day.full, sleep.month.full, sleep.week.full
- produced, not viewed: QASE A-dark: privacy.delete.cache, privacy.delete.coach, privacy.delete.insights, privacy.delete.journal, privacy.delete.preferences, privacy.delete.setAside, privacy.delete.windDown
- produced, not viewed: QASE A-light: privacy.delete.cache, privacy.delete.coach, privacy.delete.insights, privacy.delete.preferences, privacy.delete.setAside, privacy.delete.windDown
- produced, not viewed: QASE B-AX3-light: settings.appearance, settings.apple-watch, settings.health-data, settings.health-data.unauthorized, settings.help, settings.notifications, settings.notifications.denied, settings.root, settings.sounds, settings.subscription, settings.subscription.free, settings.wind-down, sleep.day.full, sleep.month.full, sleep.week.full
- produced, not viewed: QASE B-AX5-light: coach.answer, coach.answer.misbehaving, coach.answer.unavailable, coach.history, coach.hub.empty, coach.hub.full, coach.hub.learning, coach.hub.noPermission, coach.privacy, coach.quota, home.day.full, home.evening.full, insights.all.full, insights.consistency, insights.detail, insights.heart, insights.history, insights.longTerm, insights.recovery, insights.sleep, insights.timing, night.alarm, night.alarm.denied, night.breathing.finished, night.breathing.prestart, night.journal.empty, night.journal.filled, night.journal.unavailable, night.meditation.finished, night.meditation.prestart, night.meditation.running, night.reflect.draft, night.reflect.empty, night.sounds.interrupted, night.sounds.playing, night.sounds.silent, night.sounds.timer, night.tonight, night.tonight.free, night.windDown.finished, night.windDown.prestart, night.windDown.reduced, night.windDown.running30, night.windDown.running90, onboarding.goal, onboarding.health, onboarding.notifications, onboarding.paywall, onboarding.plan, onboarding.rhythm, onboarding.sample, onboarding.welcome, premium.paywall.coachQuestions, premium.paywall.loaded, premium.paywall.loading, premium.paywall.recovery30D, premium.paywall.sleepMonth, premium.paywall.unavailable, premium.paywall.weeklyReview, premium.paywall.windDown, privacy.delete.journal, privacy.delete.preferences, privacy.delete.reviews, privacy.delete.setAside, privacy.delete.windDown, privacy.deleteAll, profile.editor.goals, profile.editor.name, profile.editor.need, profile.editor.wake, profile.screen, profile.screen.learning, recovery.30d.full, recovery.7d.full, recovery.90d.full, recovery.factor.hrv, recovery.factor.restingHeartRate, recovery.factor.sleepConsistency, recovery.factor.sleepDuration, recovery.today.full, reviews.list.free, settings.about, settings.appearance, settings.apple-watch, settings.help, settings.notifications, settings.notifications.denied, settings.root, settings.sounds, settings.subscription, settings.subscription.free, settings.wind-down, sleep.day.full, sleep.month.full, sleep.week.full
- produced, not viewed: QASE C-BoldText: recovery.today.full
- produced, not viewed: QASE D-Bounded: profile.screen, profile.screen.learning
- produced, not viewed: QASE D-DoubleLength: home.day.empty, home.day.error, home.day.full, home.day.gap, home.day.learning, home.day.loading, home.day.noPermission, home.day.sleepOnly, home.day.stale, home.evening.empty, home.evening.error, home.evening.full, home.evening.gap, home.evening.learning, home.evening.loading, home.evening.noPermission, home.evening.sleepOnly, home.evening.stale, profile.screen, profile.screen.learning

## Findings seen in tier 1

- onboarding.goal on QA17Pro A-light: FINDING QA-146: the Better sleep subtitle 'A calmer wind-down and a steadier routine' is cut on one line at 11 pt ('...steadier...'): the reworded line is longer than the card's one line. Fixed in source (two lines allowed); re-shoot pending
- reviews.list on QA17Pro A-light: FINDING QA-078: the list is empty (seed not made in time); catalog changed, re-shoot pending
- reviews.list.free on QA17Pro A-light: FINDING QA-078: Reviews list shows 'Nothing here yet': the seeded reviews were not there when the list loaded (the route opens it at launch). Catalog changed to open the list from Insights after the seed; re-shoot pending
- privacy.delete.reviews on QA17Pro A-light: FINDING QA-147: captured Data management, not the confirmation (the row's button is found by label in the re-shoot; catalog fixed)
- onboarding.goal on QA17Pro A-dark: FINDING QA-146: the Better sleep subtitle 'A calmer wind-down and a steadier routine' is cut on one line at 11 pt ('...steadier...'): the reworded line is longer than the card's one line. Fixed in source (two lines allowed); re-shoot pending
- reviews.list on QA17Pro A-dark: FINDING QA-078: the list is empty (seed not made in time); catalog changed, re-shoot pending
- reviews.list.free on QA17Pro A-dark: FINDING QA-078: Reviews list shows 'Nothing here yet': the seeded reviews were not there when the list loaded (the route opens it at launch). Catalog changed to open the list from Insights after the seed; re-shoot pending
- privacy.delete.reviews on QA17Pro A-dark: FINDING QA-147: captured Data management, not the confirmation (the row's button is found by label in the re-shoot; catalog fixed)
- night.breathing.prestart on QA17Pro B-AX3-light: FINDING QA-148: Breathing running at AX3, exhale end: the phase word 'Exhale' is wider than the small circle and overprints its edge, with the countdown digit blurred mid-change; the word should stay inside or the circle keep a minimum size at accessibility sizes
- night.breathing.running on QA17Pro B-AX3-light: FINDING QA-148: Breathing running at AX3, exhale end: the phase word 'Exhale' is wider than the small circle and overprints its edge, with the countdown digit blurred mid-change; the word should stay inside or the circle keep a minimum size at accessibility sizes
- night.journal.empty on QA17Pro B-AX3-light: FINDING QA-148: Breathing running at AX3, exhale end: the phase word 'Exhale' is wider than the small circle and overprints its edge, with the countdown digit blurred mid-change; the word should stay inside or the circle keep a minimum size at accessibility sizes
- reviews.list on QA17Pro B-AX3-light: FINDING QA-151: list populated (QA-078 verified); at AX3 'Septembe/r 2026' and 'Opene/d' break inside words
- premium.paywall.windDown on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- premium.paywall.weeklyReview on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- privacy.delete.journal on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- privacy.delete.coach on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- privacy.delete.insights on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- privacy.delete.reviews on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3 (same row issue, confirmation not reached: old route); fixed in source
- privacy.delete.cache on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3: the Delete button touches the end of long titles ('Insights historyDelete') and sits against the card's right edge; the confirmation (not captured: the build used the old route) is still to shoot. Fix: stack the verb under the title at accessibility sizes
- privacy.delete.preferences on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3 (same row issue, confirmation not reached: old route); fixed in source
- privacy.delete.setAside on QA17Pro B-AX3-light: FINDING QA-149: Data management at AX3 (same row issue, confirmation not reached: old route); fixed in source
- home.day.full on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- home.evening.full on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.hub.full on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.hub.learning on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.hub.empty on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.hub.noPermission on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.answer on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.answer.misbehaving on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.answer.unavailable on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.history on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.privacy on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- coach.quota on QA17Pro B-AX5-light: FINDING: AX5 (tier 2 outside Settings/Privacy/Data/Paywall): text cut with an ellipsis: Coach composer placeholder 'Ask a follo...', History empty title 'No conversatio...', Home bedtime pill 'Bedtime 10:30 P...'; content otherwise whole and reachable
- settings.health-data on QA17Pro B-AX5-light: FINDING: AX5 Health data: 'Respiratory Rate' breaks mid-word ('Respirator/y Rate'); Settings support email breaks mid-word
- settings.help on QA17Pro B-AX5-light: FINDING: AX5 Health data: 'Respiratory Rate' breaks mid-word ('Respirator/y Rate'); Settings support email breaks mid-word
- settings.health-data.unauthorized on QA17Pro B-AX5-light: FINDING: AX5 Health data: 'Respiratory Rate' breaks mid-word ('Respirator/y Rate'); Settings support email breaks mid-word
- privacy.delete.journal on QA17Pro B-AX5-light: FINDING: AX5 Data management: the Delete verb is clipped at the right edge ('Delete' cut off) on each row, and the delete confirmation is squeezed into a narrow column; verb-under-title fix applies at AX3 but not AX5
- privacy.delete.insights on QA17Pro B-AX5-light: FINDING: AX5 Data management: the Delete verb is clipped at the right edge ('Delete' cut off) on each row, and the delete confirmation is squeezed into a narrow column; verb-under-title fix applies at AX3 but not AX5
- privacy.delete.preferences on QA17Pro B-AX5-light: FINDING: AX5 Data management: the Delete verb is clipped at the right edge ('Delete' cut off) on each row, and the delete confirmation is squeezed into a narrow column; verb-under-title fix applies at AX3 but not AX5
- onboarding.goal on QASE A-light: FINDING QA-146: SE goal page: the Better sleep subtitle is cut ('A calmer wind-down and a ste...'); fixed in source (two lines), re-shoot pending
- reviews.list on QASE A-light: FINDING QA-078: the list is empty; re-shoot pending
- reviews.list.free on QASE A-light: FINDING QA-078: the list is empty; re-shoot pending
- privacy.delete.reviews on QASE A-light: FINDING QA-147: captured Data management, not the confirmation (the row's button is found by label in the re-shoot; catalog fixed)
- onboarding.goal on QASE A-dark: FINDING QA-146: SE goal page: the Better sleep subtitle is cut ('A calmer wind-down and a ste...'); fixed in source (two lines), re-shoot pending
- reviews.list on QASE A-dark: FINDING QA-078: the list is empty; re-shoot pending
- reviews.list.free on QASE A-dark: FINDING QA-078: the list is empty; re-shoot pending
- privacy.delete.reviews on QASE A-dark: FINDING QA-147: captured Data management, not the confirmation (the row's button is found by label in the re-shoot; catalog fixed)
- recovery.today.full on QASE B-AX3-light: FINDING QA-078: Reviews list empty (seed made after load); catalog fixed, re-shoot pending. Recovery today whole
- reviews.list on QASE B-AX3-light: FINDING QA-078: Reviews list empty (seed made after load); catalog fixed, re-shoot pending. Recovery today whole
- reviews.list.free on QASE B-AX3-light: FINDING QA-078: Reviews list empty (seed made after load); catalog fixed, re-shoot pending. Recovery today whole
- premium.paywall.windDown on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- premium.paywall.weeklyReview on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- privacy.delete.journal on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- privacy.delete.coach on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- privacy.delete.insights on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- privacy.delete.reviews on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management (not the confirmation: old route)
- privacy.delete.cache on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management: Delete touches the title ('Coach historyDelete') and runs to the card's edge; fixed in source (verb under the title at accessibility sizes), re-shoot pending
- privacy.delete.preferences on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management (not the confirmation: old route)
- privacy.delete.setAside on QASE B-AX3-light: FINDING QA-149: SE AX3 Data management (not the confirmation: old route)

## Every tier-1 combination

`qa/tier1/coverage.csv` has one line per combination: area, screen, device, configuration, produced, viewed, status, result, what was seen.

