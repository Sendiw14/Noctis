# NOCTIS part 6

Every picture was looked at on a contact sheet (viewed: yes). 17 Pro status bar 9:41; the SE shows its simulator's bar.

## Findings

1. **Trial text** follows StoreKit's intro-offer eligibility and the product's real intro offer only (`showTrialCTA = isEligibleForTrial && TrialLength(product) != nil`); no layout, size or device is read. The 17 Pro and SE differed because each simulator keeps its own StoreKit purchase history (the 17 Pro had bought before). `-introEligible yes|no` (DEBUG) shows both states anywhere: the pictures below.
2. **SE notice** is pinned under the legal line on a short screen, whole at rest (se-premium.paywall.trial*).
3. **Find help** opens a built-in, region-aware sheet (device region first, a menu to choose another; Sri Lanka, US, Canada, UK, Ireland, Australia, New Zealand, India, and a generic fallback); no network is used to draw it; findahelpline.com (worldwide directory) is one tap further and is the only part that needs a connection. The numbers need an owner check before release (QA_REPORT.md section 5).
4. **Profile** already says 'Usual bedtime' and 'Usual wake' (part 5) and prints the BaselineEngine value, 11:08 PM.

| file | what | device | mode | viewed |
|---|---|---|---|---|
| phone/17pro-coach.help-dark-top.jpg | Find help sheet, device region en_US (built-in list, no network) | 17pro | dark | yes |
| phone/17pro-coach.help-light-top.jpg | Find help sheet, device region en_US (built-in list, no network) | 17pro | light | yes |
| phone/17pro-coach.help.lk-dark-top.jpg | Find help sheet, device region en_LK: Sri Lanka list | 17pro | dark | yes |
| phone/17pro-coach.help.lk-light-top.jpg | Find help sheet, device region en_LK: Sri Lanka list | 17pro | light | yes |
| phone/17pro-onboarding.paywall.trialEligible-light-bottom.jpg | Onboarding paywall, eligible | 17pro | light | yes |
| phone/17pro-onboarding.paywall.trialEligible-light-top.jpg | Onboarding paywall, eligible | 17pro | light | yes |
| phone/17pro-onboarding.paywall.trialNotEligible-light-bottom.jpg | Onboarding paywall, not eligible | 17pro | light | yes |
| phone/17pro-onboarding.paywall.trialNotEligible-light-top.jpg | Onboarding paywall, not eligible | 17pro | light | yes |
| phone/17pro-premium.paywall.trialEligible-light-top.jpg | Paywall from a lock, intro offer ELIGIBLE (-introEligible yes) | 17pro | light | yes |
| phone/17pro-premium.paywall.trialNotEligible-light-top.jpg | Paywall from a lock, NOT eligible (-introEligible no) | 17pro | light | yes |
| phone/17pro-profile.screen-light-bottom.jpg | Profile: 'Usual bedtime 11:08 PM' / 'Usual wake', the same values as every surface | 17pro | light | yes |
| phone/17pro-profile.screen-light-top.jpg | Profile: 'Usual bedtime 11:08 PM' / 'Usual wake', the same values as every surface | 17pro | light | yes |
| phone/se-coach.help-dark-top.jpg | Find help sheet, device region en_US (built-in list, no network) | se | dark | yes |
| phone/se-coach.help-light-top.jpg | Find help sheet, device region en_US (built-in list, no network) | se | light | yes |
| phone/se-coach.help.lk-dark-top.jpg | Find help sheet, device region en_LK: Sri Lanka list | se | dark | yes |
| phone/se-coach.help.lk-light-top.jpg | Find help sheet, device region en_LK: Sri Lanka list | se | light | yes |
| phone/se-onboarding.paywall.trialEligible-light-bottom.jpg | Onboarding paywall, eligible | se | light | yes |
| phone/se-onboarding.paywall.trialEligible-light-top.jpg | Onboarding paywall, eligible | se | light | yes |
| phone/se-onboarding.paywall.trialNotEligible-light-bottom.jpg | Onboarding paywall, not eligible | se | light | yes |
| phone/se-onboarding.paywall.trialNotEligible-light-top.jpg | Onboarding paywall, not eligible | se | light | yes |
| phone/se-premium.paywall.trialEligible-light-bottom.jpg | Paywall from a lock, intro offer ELIGIBLE (-introEligible yes) | se | light | yes |
| phone/se-premium.paywall.trialEligible-light-top.jpg | Paywall from a lock, intro offer ELIGIBLE (-introEligible yes) | se | light | yes |
| phone/se-premium.paywall.trialNotEligible-light-bottom.jpg | Paywall from a lock, NOT eligible (-introEligible no) | se | light | yes |
| phone/se-premium.paywall.trialNotEligible-light-top.jpg | Paywall from a lock, NOT eligible (-introEligible no) | se | light | yes |
| phone/se-profile.screen-light-bottom.jpg | Profile: 'Usual bedtime 11:08 PM' / 'Usual wake', the same values as every surface | se | light | yes |
| phone/se-profile.screen-light-top.jpg | Profile: 'Usual bedtime 11:08 PM' / 'Usual wake', the same values as every surface | se | light | yes |
