# APP_STORE_LISTING.md

Everything App Store Connect asks for, written from what the app does today (the code, `FeatureTable.swift`, `Config/Noctis.storekit`, `PRIVACY_REPORT.md`). Drafted 2026-11-01. The owner reads and
approves every line before it is entered: marketing text is a claim, and a claim the app does not back is a rejection. Character limits are Apple's.

## App information

| Field | Value | Limit |
| --- | --- | --- |
| Name | NOCTIS: Sleep & Recovery | 30 (24 used) |
| Subtitle | Sleep and recovery, on device | 30 (29 used) |
| Primary category | Health & Fitness | |
| Secondary category | Lifestyle | |
| Bundle ID | `com.noctis.app` | |
| Version / build | 1.0 (1) | |
| Languages | English | The app ships in English only. |
| Platforms | iPhone (portrait), Apple Watch | iOS 26.1 and later, watchOS 26.0 and later |
| Price | Free, with in-app subscriptions | |
| Copyright | the owner's name and year | |
| Support URL | the published support page (`Docs/site/support.html`) | required |
| Marketing URL | optional | |
| Privacy Policy URL | the published privacy page (`Docs/site/privacy.html`) | **required** |

## Promotional text (170)

Your sleep, your recovery and tonight's bedtime, worked out from Apple Health on your iPhone. No account, no ads, no tracking.

## Keywords (100, comma separated, no spaces after commas)

`sleep,recovery,hrv,bedtime,alarm,wind down,breathing,sleep sounds,watch,health,heart rate,routine`

## Description (4000)

NOCTIS turns the sleep and heart data already in Apple Health into three plain answers: how you slept, how recovered you are, and when to go to bed tonight.

Everything is worked out on your iPhone. NOCTIS has no account to make, no server, no ads and no analytics. It reads Apple Health and never writes to it.

RECOVERY
A score for today, and how it was built from your sleep, heart rate variability, resting heart rate and how regular your nights are. See what moved it against your usual, not against a stranger's average.

SLEEP
Last night in full: the time you slept, a quality score, and your stages when your Apple Watch records them. Look back over a week or a month.

TONIGHT
A bedtime for tonight from the sleep you need and the time you wake. A wake-up alarm, a wind-down for the evening, breathing exercises, meditations, and sleep sounds that your iPhone makes itself.

INSIGHTS AND REVIEWS
Patterns in your own nights, in plain words, and a weekly and a monthly review.

COACH
Ask a question about your own sleep and get an answer built from your numbers. On iPhones that support Apple Intelligence and have it turned on, Coach uses Apple's on-device model to word its answers; on other iPhones it uses fixed wording. Either way Coach runs on your iPhone and keeps its conversations there. It is not medical advice.

WIDGETS, APPLE WATCH AND SIRI
Home Screen and Lock Screen widgets, Control Center controls, a Watch app with complications and breathing, and Siri phrases for recovery, sleep and bedtime.

PRIVACY
Your sleep data stays on your iPhone. You can export or delete everything from the app, and the Privacy Center says exactly what is stored where.

NOCTIS FREE
Today's recovery and the last seven days, your last three nights and the week, a bedtime, the wake alarm, breathing, a private journal, three sleep sounds, three Coach questions a day, a small widget and the core Watch pages.

NOCTIS PREMIUM
Recovery over 30 and 90 days and its factors, the sleep month and every night, all insights and their history, unlimited Coach, a personal wind-down window and wind-down sessions, meditations, three more sleep sounds, larger widgets, more Watch pages and complications, and the full weekly and monthly reviews.

Subscriptions: NOCTIS Premium is NOCTIS Premium (Yearly), with a one-week free trial, and NOCTIS Premium (Monthly). Payment is charged to your Apple Account at confirmation of purchase, or at the end of the free trial. The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period. You can manage or cancel it in your Apple Account settings. Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

NOCTIS isn't a medical device and doesn't diagnose or treat any condition. If you are worried about your health, talk to a doctor.

## What's New (version 1.0)

First release.

## Subscriptions in App Store Connect

One subscription group, **NOCTIS Premium**. The identifiers must match `Config/Noctis.storekit` exactly.

| Product ID | Display name | Period | Price in the test file | Offer |
| --- | --- | --- | --- | --- |
| `com.noctis.app.premium.yearly` | NOCTIS Premium (Yearly) | 1 year | 39.99 | Free trial, 1 week |
| `com.noctis.app.premium.monthly` | NOCTIS Premium (Monthly) | 1 month | 6.99 | none |

The prices in `Noctis.storekit` are for testing. Set the real price in App Store Connect; the paywall reads the price from the store and never hard-codes one. Each subscription needs a
display name, a description and a review screenshot of the paywall. Family Sharing is off in the test file; decide it in App Store Connect on purpose, and keep the two in step.

## App Review information

**Sign-in:** none needed. NOCTIS has no account. Sign in with Apple is optional and local (Profile). Account deletion is in Settings, Data management, "Delete account and data".

**Notes for the reviewer (paste into the Notes field):**

NOCTIS reads sleep, heart rate, resting heart rate, heart rate variability and respiratory rate from Apple Health, read only. Without Health data the app shows its learning and empty states; the
onboarding includes one night clearly labelled Sample. To see the app with data, add sleep samples in the Health app (Browse, Sleep) or use a device that has an Apple Watch's sleep tracking.

There is no server, no account and no analytics; the app makes no network requests of its own. The only network use is Apple's: StoreKit for the subscription.

Subscriptions: open Settings, then Subscription, or tap a locked item. The paywall shows the price, the trial and the renewal terms. "Restore Purchases" is on the paywall and in Settings.
"Manage subscription" opens Apple's page.

Permissions: Health (read), Notifications (reminders), and AlarmKit (the wake alarm). Sleep sounds use the audio background mode so a sound can play with the screen locked.

Coach (the fifth tab) answers questions about the person's own sleep and recovery. How it works:
- On iPhones where Apple Intelligence is available and turned on, Coach asks Apple's on-device language model (the Foundation Models framework) to write the answer, and, for a question its patterns do not recognise, to say which topic the question is about. The model runs on the iPhone; NOCTIS has no server and no other model, and sends nothing off the device.
- On every other iPhone (not eligible, Apple Intelligence off, model not ready, language not supported) Coach builds the answer from fixed sentence templates and the same numbers. The reviewer can see this path on any device without Apple Intelligence.
- Every number in an answer is a value NOCTIS supplied, not one the model made up: a draft is shown only after NOCTIS checks it (digits, percent signs and number words are allowed only as values NOCTIS supplied, no wording from a list of medical and diagnostic phrases, patterns hedged, a caution when confidence is not high). A draft that fails, or takes longer than 15 seconds, is replaced by the template answer. The answers are not clinically validated.
- Questions about a medical condition get a fixed reply that points to a doctor; a crisis question gets a fixed reply with helpline numbers. The reply itself is fixed text: no model-written words and no personal data. A question that NOCTIS's own patterns recognise as medical or crisis never reaches the model. A question no pattern recognises is first classified by the on-device model, which reads only the question text (never the person's numbers); if it classifies it as medical or crisis, the same fixed reply is shown. A crisis exchange is neither saved nor logged.
- Coach conversations stay on the iPhone, can be exported and deleted in Settings, Data management, and are excluded from device backups.
- Coach is English only.

NOCTIS isn't a medical device and says so on the welcome screen, the paywall, About and the Apple Watch.

**Contact:** the owner's name, phone number and email (required by App Store Connect).

## Coach and generative AI (what to say, and what not to say)

Written 2026-11-02 from the code (`CoachKit/AIService.swift`, `FoundationModelsProvider.swift`, `SystemLanguageModelBackend.swift`, `CoachSafetyValidator.swift`) after the pre-launch audit found the earlier review notes ("fixed wording") did not match it.

| Question | Answer, from the code |
| --- | --- |
| Does Coach use a generative model? | **Yes, on supported iPhones**: Apple's on-device `SystemLanguageModel` (Foundation Models). `CoachFeatureFlags.aiAppleIntelligence` is on by default. |
| On which devices? | Only where the system reports the model available. NOCTIS maps the system's reasons (`deviceNotEligible`, `notEnabled`, `modelNotReady`, `unsupportedLanguage`) and falls back; it does not assume support. |
| What if it is not available? | Template answers: fixed sentence patterns filled from the person's numbers, checked by the same validator. |
| Is any remote or third-party model used? | No. `aiRemote` is off; there is no transport, endpoint or key. |
| What does the model see? | The question, the topic, facts worked out from the person's data (recovery today, last night, usual bedtime and wake, week's average, sleep need, wake time, goals) and short summaries of the last two turns. Never the name, the Journal or raw Health readings. |
| What is checked before an answer is shown? | `CoachSafetyValidator`: required fields, length limits, no digit, percent or number word outside a fact token, every token a known fact, banned-language list, hedged patterns, caution when confidence is not high, destinations only real screens. |
| Medical and crisis? | The reply is fixed text (no model-written words, no personal data). A pattern match never reaches the model; a question no pattern recognises is classified first by the on-device model, which reads only the question, and a medical or crisis classification gets the same fixed reply. Crisis exchanges are not kept or logged. The helpline list is built in and flagged for the owner to verify before release. |
| Claims to avoid | "Works on every iPhone", "AI-powered insights" as a headline, "clinically validated" or "accurate", any diagnosis or treatment wording. Say "on-device", "where your iPhone supports it", "not medical advice". |
| Not verified | The model path on a real Apple Intelligence device and the template path on a device without it (`DEVICE_TEST_CHECKLIST.md`). The simulator does not prove either. |

## Age rating

Answer the questionnaire from the app: no user-generated content, no web access, no gambling, no violence, no mature themes, no contests. The one topic that applies is health and
wellness. **The owner enters the answers and reads the rating they get; this document does not state a rating.**

## App Privacy ("nutrition label")

Section 4 of `Docs/PRIVACY_REPORT.md` has the draft answers and is the source. In short: data not collected, no tracking, none linked to the person. The owner approves them there first.
The app's own `PrivacyInfo.xcprivacy` files (one per target) say the same, and `PrivacyManifestTests` holds them to the code.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO` in both app targets (`project.yml`). The app uses no encryption of its own beyond Apple's system frameworks. The owner confirms this in App Store Connect.

## Screenshots

Required: one set at 6.9 inch (1320 x 2868). Up to 10. Apple Watch screenshots are needed because the app has a Watch app (take the size App Store Connect asks for at upload).

Candidates already captured on a 17 Pro Max at 1320 x 2868 (`~/qa-work/matrix-all/A-light/QA17ProMax` and `A-dark`): `home.day.full`, `home.evening.full`, `sleep.day.full`, `sleep.week.full`,
`sleep.month.full`, `recovery.today.full`, `recovery.30d.full`, `onboarding.paywall` and `premium.paywall.loaded` (the `__top.png` files). **Do not upload these as they are**: their
status-bar clocks read 9:59, 10:01 and 10:03 and not one time, and Insights, Coach and Tonight are missing from that set.

Before submission: boot a 17 Pro Max simulator, run `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`,
capture Home, Sleep, Recovery, Insights, Coach, Tonight and the paywall with the app's own mock scenario, and look at every picture before uploading. Use sample data only; the screens never show a name.
Do not put text in the screenshots that the app does not show.
