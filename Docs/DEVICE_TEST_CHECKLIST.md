# DEVICE_TEST_CHECKLIST.md

What the simulator cannot show and a real iPhone and Apple Watch must. Each row names what to do, what a pass looks like, and the ledger row it settles. Mark a row only when it was
done on the device, and write the date and the device model beside it. Nothing is ticked yet.

Set up: an iPhone on the minimum iOS (26.1 if one is available) and one on the latest, a paired Apple Watch, a Sandbox Apple Account for purchases, and a Health store with at least
two weeks of sleep, heart rate and HRV (the Watch's own sleep tracking provides it).

## Health and background

- [ ] Fresh install, grant Health read access: Home shows last night, a recovery score and tonight's bedtime from real data. (Settles the real-data side of QA-121.)
- [ ] Deny Health access: the "no permission" state shows and nothing crashes; re-enable in Settings and the app recovers without a restart.
- [ ] Sleep overnight with the Watch: in the morning the widgets and Home agree with the Health app's night. Background delivery (R46) refreshes the widget before the app is opened. iOS chooses the time; note it.
- [ ] A night with a gap (Watch off for part of it) and a night with no data: wording matches the empty and gap states.

## Purchases (Sandbox)

- [ ] Yearly with the one-week trial: Premium unlocks everywhere (Home locks, Coach quota, widgets, Watch pages, Siri phrases, wind-down notification wording).
- [ ] Cancel auto-renew: Premium stays to the end date and the page says it will not renew.
- [ ] Let a short Sandbox period expire with the app closed, then open it: the plan reads free and the locked screens return. Also check the widgets, complications and Siri **before** the app is opened (the known gap in `POST_LAUNCH.md`) and write down what they show.
- [ ] Restore Purchases on a second device. Refund path if the Sandbox allows it.

## Alarm, notifications, wind-down

- [ ] Wake alarm (AlarmKit) rings with the phone locked and on silent, snooze works, the snooze countdown shows on the Lock Screen.
- [ ] The three reminder types arrive at their times; each tap opens its screen (QA-133 was checked with the app's own flag, not a real delivery).
- [ ] Wind-down Live Activity starts, shows on the Lock Screen, the Dynamic Island and the Watch Smart Stack, and ends on its own.
- [ ] A sleep sound plays with the screen locked, the timer stops it, and the Control Center control matches.

## Apple Watch

- [ ] Pairing sends the summary within a minute; five pages match the iPhone.
- [ ] Four complications update through the day and at the day change.
- [ ] Breathing on the Watch with haptics on and off.
- [ ] Watch with the iPhone out of range: the last summary shows with its age.

## Feel and performance (device numbers)

- [ ] Cold launch to Home on the oldest supported iPhone: note the time (budget to set from this run).
- [ ] Scroll Sleep month and Recovery 90D with 730 nights loaded: no dropped frames you can see.
- [ ] Memory in Instruments after the 20-lap loops on Recovery, Insights and Coach: flat.
- [ ] Battery: one night with the app and Watch complications; note the drain.

## Accessibility

- [ ] VoiceOver through onboarding, Home, Sleep, Recovery, the paywall and the wind-down; every control is named and the order is sensible.
- [ ] Largest accessibility text size on the smallest iPhone: nothing is cut or overprinted on the screens listed as OPEN in `QA_LEDGER.md`.
- [ ] Smart Invert and Reduce Motion (QA-057, not visible in a screenshot).
- [ ] Voice Control and Switch Control reach the paywall's buttons and the delete confirmations.
