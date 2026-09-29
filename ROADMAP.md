# ROADMAP.md
Unbuilt features (APP_RULES.md R19). Each one shows "Coming soon" or is not reachable until built. This file must be empty before release.

- Recovery tab. Home's recovery card opens its own Recovery detail.
- Insights tab
- Coach tab
- Profile. The avatar button at the top right of Home, and `noctis://profile`, open a "Coming soon" screen.
- Sleep quality on Home's Last night card. The engine exists (`sleep-quality-v1`, shown in the Sleep tab); Home's card doesn't show it yet.
- Free vs Premium gating for Sleep: Month, the quality factors and the 14-night picker. All of Sleep is open until the paywall decides.
- Sleep share card. Home's "Share this night" card stays the only share.
- Wind-down on Home's Tonight card (R19: no button until it exists).
- Data Management (Profile). One place to erase what NOCTIS keeps. `NoctisDataRegistry.shared.eraseAll()` already reaches everything registered: the saved Home snapshot (`home-snapshot.json`, the last launch's derived Home data, used to draw Home in its first frame) and the insight history. Before release the profile store and the onboarding state must register too, and nothing that keeps Health-derived data may sit outside the registry (R23).
