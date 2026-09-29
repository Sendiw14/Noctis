# ROADMAP.md
Unbuilt features (APP_RULES.md R19). Each one shows "Coming soon" or is not reachable until built. This file must be empty before release.

- Sleep tab. Home's Last night and This week cards open it.
- Recovery tab. Home's recovery card opens its own Recovery detail.
- Insights tab
- Coach tab
- Profile. The avatar button at the top right of Home, and `noctis://profile`, open a "Coming soon" screen.
- Sleep quality on Home's Last night card. It needs a tested sleep-quality engine first (R18).
- Wind-down on Home's Tonight card (R19: no button until it exists).
- Data Management (Profile). One place to erase what NOCTIS keeps. `NoctisDataRegistry.shared.eraseAll()` already reaches everything registered: the saved Home snapshot (`home-snapshot.json`, the last launch's derived Home data, used to draw Home in its first frame) and the insight history. Before release the profile store and the onboarding state must register too, and nothing that keeps Health-derived data may sit outside the registry (R23).
