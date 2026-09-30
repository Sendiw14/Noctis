# ROADMAP.md
Unbuilt features (APP_RULES.md R19). Each one shows "Coming soon" or is not reachable until built. This file must be empty before release.

- Coach tab. It shows the scaffold with its rose field and a "Coming soon" card (R27); the tab itself is not built.
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
- The Coach reading `InsightRecord`. The records are the safe context (typed numbers, no raw HealthKit data); the Coach tab is not built.
