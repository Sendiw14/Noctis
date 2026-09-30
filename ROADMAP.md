# ROADMAP.md
Unbuilt features (APP_RULES.md R19). Each one shows "Coming soon" or is not reachable until built. This file must be empty before release.

- Profile. The avatar button at the top right of Home, and `noctis://profile`, open a "Coming soon" screen.
- Free vs Premium gating for Sleep: Month, the quality factors and the 14-night picker. All of Sleep is open until the paywall decides.
- Sleep share card. Home's "Share this night" card stays the only share.
- Wind-down on Home's Tonight card (R19: no button until it exists).
- Data Management (Profile). One place to erase what NOCTIS keeps. `NoctisDataRegistry.shared.eraseAll()` already reaches everything registered: the saved Home snapshot (`home-snapshot.json`, the last launch's derived Home data, used to draw Home in its first frame), the insight history and the stored insights (`insights.json`: every generated insight's typed numbers and whether it is new, seen or dismissed, with complete file protection and excluded from backups). Before release the profile store and the onboarding state must register too, and nothing that keeps Health-derived data may sit outside the registry (R23).
- Free vs Premium gating for Recovery: free is Today and 7D; premium is 30D, 90D and each factor's history. All of Recovery is open until the paywall decides.
- Recovery share card. Home's "Share this night" card stays the only share.
- Recovery load factor from workouts. The model has four factors (sleep, HRV, resting heart rate, consistency); training load isn't one until workouts are read and tested.
- Free vs Premium gating for Insights: free is the featured story plus one recent insight; premium is everything (the rest of Recent, Your records, History, every detail). All of Insights is open until the paywall decides.
- Activity insights. Nothing about workouts or steps is generated until workout data is read and the rules are tested (Recovery's load factor waits on the same thing).
- Insight share card. Home's "Share this night" card stays the only share.
- Remote model (`aiRemote`). `RemoteModelProvider`, its request and response types and its privacy filter exist and are tested; there is no transport, no endpoint and no key, and the flag is off. Nothing leaves the device until a transport, the consent screen and the privacy review exist.
- Coach history sync. Coach's conversations (`AIConversation`, `AIMessage`) stay on this device: no CloudKit, no backup. Syncing them across devices needs its own privacy decision and an encrypted zone.
- Free vs Premium gating for Coach. Proposal: free is 3 questions a day (the suggested questions and typed ones count alike; a fixed reply does not); premium is unlimited questions and History. All of Coach is open until the paywall decides.
- Localised Coach and crisis resources. The router's patterns, every scripted and template sentence, and the crisis reply (findahelpline.com) are English only; each language needs its own patterns, copy, banned-word list and a local emergency resource before Coach is offered in it.
- Coach share. Nothing in Coach can be shared; Home's "Share this night" card stays the only share.
- Voice input. The text field takes typing only.
