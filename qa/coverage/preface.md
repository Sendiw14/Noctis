## How a combination is produced, and what "viewed" means

- **Screens.** `ScreenCatalog` (`Packages/NoctisKit/QA/QACatalog`) lists every screen, sheet and state the Debug launch arguments can reach (193 iPhone entries
  plus 19 for the Apple Watch). A unit test (`ScreenCatalogTests`) fails on a duplicate, on an `AppRoute` case no entry opens, on a route that does not
  parse, on a Settings page, Recovery range or factor with no entry and on a launch flag no source reads. `qa/coverage/catalog.json` is its export.
- **Configurations.** `scripts/qa_configs.py` names each one; `scripts/qa_matrix.py` puts the simulator in it (`simctl ui` for appearance, content size and
  Increase Contrast; the simulated device's `com.apple.Accessibility` defaults for the rest; Xcode's own launch arguments for the pseudolanguages and
  right-to-left) and runs `QAMatrixTests`. **Before a screen is photographed the app is asked what it sees** (`-noctisEnvironmentProbe`: text size, bold,
  reduce motion, reduce transparency, differentiate without color, button shapes, on/off labels, invert, contrast, color scheme, layout direction, locale,
  calendar, time zone, hour format, first weekday) and the run fails if it is not the configuration it claims to be. `environmentOK` is that check.
- **Produced** means a top screenshot (and, for a page that scrolls, every page down to the bottom) exists for the combination and the screen reached
  its ready state. **Viewed** means a contact sheet that contains the combination's top and bottom was looked at at a size where its text can be read
  (`scripts/qa_sheets.py`: 340 to 460 pt a phone, the screen's name and the configuration's above each); `qa/coverage/viewed.tsv` is the list of sheets that
  were, with what was seen. Zoomed crops were taken where the text on a sheet was too small. **Result** is the worst of what was seen: PASS, NOTE (something
  seen that is not a defect, recorded) or FINDING (a ledger row).
- **UNVERIFIED** is everything else: not produced (and why, in the report), or produced and not looked at. It is never counted as a pass.

### What a screenshot cannot show

- **Reduce Motion** is a behavior: a still image of a screen with it on is the same as with it off. The configuration is verified by the probe and the
  screens are produced and viewed (nothing may depend on motion to be understood); what the setting changes is held by `HomeMotionQATests` and the
  motion tests of each screen (R2).
- **Smart Invert** is applied by the display, outside the app's layers: the simulator's screenshots are not inverted. The probe says the app sees it; the
  images prove only that nothing is lost when the app is told. Whether images and the Recovery ring are exempted correctly (`accessibilityIgnoresInvertColors`)
  needs a device or the simulator's screen recording, and is UNVERIFIED here.
- **Accented, Double-Length and Bounded String** change only what is looked up in a bundle's strings. A literal that is not looked up (an interpolated
  sentence) is not changed, which is itself what the run shows: `Localizations/needs-translation.csv` lists those.
