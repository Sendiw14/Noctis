# Unit tests on the final tree (formatted, commit b09478f)

Command: cd Packages/NoctisKit && xcodebuild test -scheme NoctisKit-Package -destination <iPhone 18 Pro, iOS 27.0>
✔ Test run with 2617 tests in 355 suites passed after 638.578 seconds.

Purchase tests (scheme NOCTIS-Store, app-hosted, StoreKit test session over Config/Noctis.storekit):
━ Test run with 23 tests in 1 suite passed after 9.176 seconds with 1 known issue.
━ Test run with 23 tests in 1 suite passed after 8.961 seconds with 1 known issue.
━ Test run with 23 tests in 1 suite passed after 9.256 seconds with 1 known issue.
(two earlier runs of the same tests on this tree failed intermittently: products did not load once, a cancel-renewal timing assertion once; the untouched pre-cleanup tree passed 4 of 4 runs. See QA ledger.)

UI test: NoRequestsQATests (the app makes no network request across tabs, Coach, Profile, Settings, Privacy):
	 Executed 1 test, with 0 failures (0 unexpected) in 61.281 (61.283) seconds
