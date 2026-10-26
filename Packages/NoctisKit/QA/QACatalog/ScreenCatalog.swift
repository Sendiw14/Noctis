import Foundation

// QA part 3 (QA_COVERAGE.md, APP_RULES.md R67): one list of every screen, sheet and state the app can be put in with its DEBUG launch arguments.
// It is data only and it is linked by the unit tests and the UI tests, never by the app: the launch flags it names exist in the Debug build alone
// (the Release symbol check scans the app's binaries, and this library is not in them).
//
// A test asserts that no two entries share an id and that every `AppRoute` case is the route of at least one entry. QAMatrixTests visits every entry
// under a configuration; QA_COVERAGE.md says, per entry and configuration, whether the screen was produced, whether it was looked at, and what was seen.

/// One screen or state of the app.
public struct CatalogScreen: Sendable, Hashable, Identifiable {
    public enum Area: String, Sendable, CaseIterable, Hashable {
        case onboarding, home, sleep, recovery, insights, coach, night, reviews, premium, profile, settings, privacy, widgets, watch
    }

    /// What it is, which decides how it is photographed (a sheet has no tab bar behind it; a gallery is not scrolled).
    public enum Surface: String, Sendable, Hashable {
        case tab, pushed, sheet, fullScreen, gallery
    }

    /// Where it runs. The Apple Watch app is its own target on its own simulator.
    public enum Platform: String, Sendable, Hashable {
        case iPhone, watch
    }

    /// What to do once the app is up, to get from the route's screen to this one.
    public enum Step: Sendable, Hashable {
        /// A tab bar button, by label.
        case tapTab(String)
        /// A button (or any control) by its label.
        case tapLabel(String)
        /// An element whose label begins with this (a row whose label carries its value: "Sleep need, 8h"). A container's identifier replaces its
        /// descendants' on this OS, so a row inside a card is found by its label.
        case tapLabelPrefix(String)
        /// Any element by its accessibility identifier.
        case tapIdentifier(String)
        /// Scrolls up until the top of the page.
        case scrollToTop
        /// Waits for an element by its accessibility identifier (a screen that arrives after a tap).
        case waitFor(String)
        /// Waits for any element whose identifier begins with this (rows that have an id made at run time).
        case waitForPrefix(String)
        /// The navigation bar's back button.
        case back
        /// Types this text into the first text field on screen (Coach's question field).
        case type(String)
        /// Pauses this many seconds (an answer that takes a moment to arrive, a banner, a ringing alarm).
        case wait(Double)
    }

    public let id: String
    public let area: Area
    public let title: String
    /// The Debug launch arguments (everything but the clock and the reset, which the harness adds).
    public let arguments: [String]
    /// The `AppRoute(name:)` this entry opens (`-noctisInitialRoute`), when it opens one.
    public let route: String?
    /// The `AppRoute` case (by `AppRoute.name`) a screen reached by taps stands for, when the route alone cannot name it (an insight's page needs
    /// an id that only exists once the insights have been built).
    public let opens: String?
    public let steps: [Step]
    /// An accessibility identifier that is on screen when the entry is ready; nil: the harness waits for the screen to settle.
    public let ready: String?
    public let surface: Surface
    public let platform: Platform
    /// Tabs, Tonight, Wind-down, onboarding, the paywall and Settings: they get every configuration.
    public let tierOne: Bool
    /// Whether the page scrolls (the harness photographs both ends).
    public let scrolls: Bool
    /// Needs an onboarding that has not been completed (the harness does not skip it).
    public let showsOnboarding: Bool
    /// Shows the App Store's plans: the harness starts a StoreKit test session on `Noctis.storekit` so the products load (`-mockStoreLoad` replaces it).
    public let needsStore: Bool

    public init(
        id: String, area: Area, title: String, arguments: [String] = [], route: String? = nil, opens: String? = nil, steps: [Step] = [], ready: String? = nil,
        surface: Surface = .tab, platform: Platform = .iPhone, tierOne: Bool = false, scrolls: Bool = true, showsOnboarding: Bool = false,
        needsStore: Bool = false
    ) {
        self.id = id
        self.area = area
        self.title = title
        self.arguments = arguments
        self.route = route
        self.opens = opens
        self.steps = steps
        self.ready = ready
        self.surface = surface
        self.platform = platform
        self.tierOne = tierOne
        self.scrolls = scrolls
        self.showsOnboarding = showsOnboarding
        self.needsStore = needsStore
    }
}

public enum ScreenCatalog {
    /// The arguments every main-app entry starts from: mock Health, no onboarding, Home by day. The scenario is added once, by the entry (the first
    /// occurrence of a flag is the one the app reads).
    public static func base(scenario: String = "full", mode: String = "day") -> [String] {
        ["-useMockHealth", "-mockScenario", scenario, "-noctisSkipOnboarding", "-homeMode", mode]
    }

    /// The states a tab is looked at in (the brief's "key states"), by name, with the flags that put the app in them.
    public struct State: Sendable, Hashable {
        public let name: String
        public let scenario: String
        public let extra: [String]

        public static let full = State(name: "full", scenario: "full", extra: [])
        public static let sleepOnly = State(name: "sleepOnly", scenario: "sleepOnly", extra: [])
        public static let learning = State(name: "learning", scenario: "learning", extra: [])
        public static let empty = State(name: "empty", scenario: "empty", extra: [])
        public static let noPermission = State(name: "noPermission", scenario: "full", extra: ["-mockUnauthorized"])
        public static let gap = State(name: "gap", scenario: "gap", extra: [])
        public static let stale = State(name: "stale", scenario: "stale", extra: [])
        /// Health's first answer is slow: the skeletons stay on screen.
        public static let loading = State(name: "loading", scenario: "full", extra: ["-mockLatency", "240"])
        public static let error = State(name: "error", scenario: "full", extra: ["-noctisHealthQueryFails"])

        public static let all: [State] = [.full, .sleepOnly, .learning, .empty, .noPermission, .gap, .stale, .loading, .error]
    }

    /// The same mock scenarios as one list.
    public static let states = State.all

    private static func tab(
        _ id: String, _ area: CatalogScreen.Area, _ title: String, route: String?, state: State, mode: String = "day", extra: [String] = [],
        tierOne: Bool = false
    ) -> CatalogScreen {
        var arguments = base(scenario: state.scenario, mode: mode) + state.extra + extra
        if let route { arguments += ["-noctisInitialRoute", route] }
        return CatalogScreen(id: id, area: area, title: title, arguments: arguments, route: route, tierOne: tierOne)
    }

    // MARK: Onboarding

    static let onboarding: [CatalogScreen] = [
        ("welcome", "Welcome"), ("name", "Name, after signing in with Apple"), ("goal", "Goal"), ("rhythm", "Rhythm"), ("sample", "Sample"),
        ("health", "Health"), ("notifications", "Notifications"),
        ("plan", "Plan"), ("paywall", "Paywall step"),
    ].map { step, title in
        CatalogScreen(
            id: "onboarding.\(step)", area: .onboarding, title: "Onboarding: \(title)",
            arguments: ["-useMockHealth", "-noctis.onboarding.step", step] + (step == "name" ? ["-noctisMockGivenName", "Sendiw"] : []), surface: .fullScreen,
            tierOne: true, showsOnboarding: true, needsStore: step == "paywall"
        )
    }

    // MARK: The tabs

    static let home: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for state in states {
            list.append(tab("home.day.\(state.name)", .home, "Home by day: \(state.name)", route: "home", state: state, tierOne: state == .full))
            list.append(
                tab(
                    "home.evening.\(state.name)", .home, "Home in the evening: \(state.name)", route: "home", state: state, mode: "evening",
                    tierOne: state == .full))
        }
        return list
    }()

    static let sleep: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for (range, route) in [("day", "sleep"), ("week", "sleep:week"), ("month", "sleep:month")] {
            for state in states {
                list.append(
                    tab(
                        "sleep.\(range).\(state.name)", .sleep, "Sleep, \(range): \(state.name)", route: route, state: state,
                        tierOne: state == .full && range == "day"))
            }
        }
        return list
    }()

    static let recovery: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for (range, route) in [("today", "recovery"), ("7d", "recovery:7d"), ("30d", "recovery:30d"), ("90d", "recovery:90d")] {
            for state in states {
                list.append(
                    tab(
                        "recovery.\(range).\(state.name)", .recovery, "Recovery, \(range): \(state.name)", route: route, state: state,
                        tierOne: state == .full && range == "today"))
            }
        }
        // A factor's page, over its range's nights (the route carries range and factor: "recovery:30d:hrv").
        for factor in ["sleepDuration", "sleepConsistency", "hrv", "restingHeartRate"] {
            list.append(
                tab("recovery.factor.\(factor)", .recovery, "Recovery factor: \(factor)", route: "recovery:30d:\(factor)", state: .full)
            )
        }
        return list
    }()

    static let insights: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for state in states {
            list.append(tab("insights.all.\(state.name)", .insights, "Insights: \(state.name)", route: "insights", state: state, tierOne: state == .full))
        }
        for category in ["sleep", "recovery", "timing", "consistency", "heart", "longTerm"] {
            list.append(tab("insights.\(category)", .insights, "Insights, \(category) chip", route: "insights:\(category)", state: .full))
        }
        list.append(
            CatalogScreen(
                id: "insights.detail", area: .insights, title: "An insight's page", arguments: base() + ["-noctisInitialRoute", "insights"], route: "insights",
                opens: "insight", steps: [.tapIdentifier("insights.featured")], ready: "insights.detail", surface: .pushed
            )
        )
        list.append(
            CatalogScreen(
                id: "insights.history", area: .insights, title: "Insight history", arguments: base() + ["-noctisInitialRoute", "insights"], route: "insights",
                steps: [.tapIdentifier("insights.history")], ready: "insights.history.screen", surface: .pushed
            )
        )
        return list
    }()

    static let coach: [CatalogScreen] = {
        let coachBase = base() + ["-noctisInitialRoute", "coach"]
        return [
            CatalogScreen(id: "coach.hub.full", area: .coach, title: "Coach hub", arguments: coachBase, route: "coach", tierOne: true),
            CatalogScreen(
                id: "coach.hub.learning", area: .coach, title: "Coach hub while learning",
                arguments: base(scenario: "learning") + ["-noctisInitialRoute", "coach"], route: "coach"
            ),
            CatalogScreen(
                id: "coach.hub.empty", area: .coach, title: "Coach hub with no data", arguments: base(scenario: "empty") + ["-noctisInitialRoute", "coach"],
                route: "coach"
            ),
            CatalogScreen(
                id: "coach.hub.noPermission", area: .coach, title: "Coach hub without Health access",
                arguments: coachBase + ["-mockUnauthorized"], route: "coach"
            ),
            CatalogScreen(
                id: "coach.answer", area: .coach, title: "Coach answer", arguments: base() + ["-mockAI", "good", "-noctisInitialRoute", "coach:recovery"],
                route: "coach:recovery", ready: "coach.conversation", surface: .pushed
            ),
            CatalogScreen(
                id: "coach.answer.misbehaving", area: .coach, title: "Coach answer the model got wrong",
                arguments: base() + ["-mockAI", "misbehaving", "-noctisInitialRoute", "coach:recovery"], route: "coach:recovery", ready: "coach.conversation",
                surface: .pushed
            ),
            CatalogScreen(
                id: "coach.answer.unavailable", area: .coach, title: "Coach with the model unavailable",
                arguments: base() + ["-mockAI", "unavailable", "-noctisInitialRoute", "coach:recovery"], route: "coach:recovery", surface: .pushed
            ),
            CatalogScreen(
                id: "coach.history", area: .coach, title: "Coach history", arguments: base() + ["-mockAI", "good", "-noctisInitialRoute", "coach"],
                route: "coach",
                steps: [.tapIdentifier("coach.question.recovery.lower"), .waitFor("coach.conversation"), .back, .scrollToTop, .tapIdentifier("coach.history")],
                ready: "coach.history.screen", surface: .pushed
            ),
            CatalogScreen(
                id: "coach.privacy", area: .coach, title: "Coach privacy sheet", arguments: coachBase, route: "coach",
                steps: [.tapLabel("How Coach uses your data")], ready: "coach.privacy.done", surface: .sheet
            ),
            CatalogScreen(
                id: "coach.quota", area: .coach, title: "Coach, free plan with the day's questions used",
                arguments: base() + ["-forceTier", "free", "-noctis.coach.quota", "2099-01-01|99", "-noctisInitialRoute", "coach"], route: "coach"
            ),
            // Typed questions the scripted replies answer (the final gallery): a medical one and a crisis one.
            CatalogScreen(
                id: "coach.medical", area: .coach, title: "Coach, a medical question (scripted reply)", arguments: base() + ["-noctisInitialRoute", "coach"],
                route: "coach", opens: "coach",
                steps: [.type("Do I have sleep apnea?"), .tapLabel("Send"), .wait(4)], ready: nil, surface: .pushed
            ),
            CatalogScreen(
                id: "coach.crisis", area: .coach, title: "Coach, a crisis message (scripted reply)", arguments: base() + ["-noctisInitialRoute", "coach"],
                route: "coach", opens: "coach",
                steps: [.type("I want to hurt myself"), .tapLabel("Send"), .wait(4)], ready: nil, surface: .pushed
            ),
            CatalogScreen(
                id: "coach.help.lk", area: .coach, title: "Coach, Find help sheet on a Sri Lanka device (region en_LK)",
                arguments: base() + ["-noctisInitialRoute", "coach", "-AppleLocale", "en_LK"], route: "coach", opens: "coach",
                steps: [.type("I want to hurt myself"), .tapLabel("Send"), .wait(4), .tapIdentifier("coach.findHelp"), .wait(1.5)], ready: nil, surface: .sheet
            ),
            CatalogScreen(
                id: "coach.help", area: .coach, title: "Coach, Find help sheet (built-in list for the region)",
                arguments: base() + ["-noctisInitialRoute", "coach"], route: "coach", opens: "coach",
                steps: [.type("I want to hurt myself"), .tapLabel("Send"), .wait(4), .tapIdentifier("coach.findHelp"), .wait(1.5)], ready: nil, surface: .sheet
            ),
        ]
    }()

    // MARK: The night

    static let night: [CatalogScreen] = {
        let tonight = base(mode: "evening") + ["-noctisInitialRoute", "tonight"]
        func pushed(
            _ id: String, _ title: String, route: String, extra: [String], ready: String? = nil, tierOne: Bool = false, steps: [CatalogScreen.Step] = []
        ) -> CatalogScreen {
            CatalogScreen(
                id: id, area: .night, title: title, arguments: base(mode: "evening") + extra + ["-noctisInitialRoute", route], route: route, steps: steps,
                ready: ready,
                surface: .pushed, tierOne: tierOne
            )
        }
        return [
            CatalogScreen(
                id: "night.tonight", area: .night, title: "Tonight", arguments: tonight, route: "tonight", ready: "tonight.screen", surface: .pushed,
                tierOne: true),
            pushed("night.tonight.free", "Tonight, free plan", route: "tonight", extra: ["-forceTier", "free"], ready: "tonight.screen"),
            pushed("night.alarm", "Alarm sheet", route: "alarm", extra: ["-mockAlarm", "authorized"], ready: "alarm.sheet"),
            pushed("night.alarm.denied", "Alarm sheet, denied", route: "alarm", extra: ["-mockAlarm", "denied"], ready: "alarm.sheet"),
            pushed("night.sounds.silent", "Sleep sounds", route: "sounds", extra: ["-mockSound", "silent"], ready: "sounds.screen"),
            pushed("night.sounds.playing", "Sleep sounds, playing", route: "sounds", extra: ["-mockSound", "playing:rain"], ready: "sounds.screen"),
            pushed("night.sounds.timer", "Sleep sounds, with a timer", route: "sounds", extra: ["-mockSound", "timer:rain:30"], ready: "sounds.screen"),
            pushed(
                "night.sounds.interrupted", "Sleep sounds, interrupted", route: "sounds", extra: ["-mockSound", "interrupted:ocean"], ready: "sounds.screen"),
            pushed(
                "night.windDown.prestart", "Wind-down, before starting", route: "wind-down", extra: ["-mockWindDown", "prestart"], ready: "windDown.screen",
                tierOne: true),
            pushed(
                "night.windDown.running30", "Wind-down, 30% in", route: "wind-down", extra: ["-mockWindDown", "running:0.3"], ready: "windDown.screen",
                tierOne: true),
            pushed(
                "night.windDown.running90", "Wind-down, 90% in", route: "wind-down", extra: ["-mockWindDown", "running:0.9"], ready: "windDown.screen",
                tierOne: true),
            pushed(
                "night.windDown.finished", "Wind-down, finished", route: "wind-down", extra: ["-mockWindDown", "finished"], ready: "windDown.screen",
                tierOne: true),
            pushed(
                "night.windDown.reduced", "Wind-down, running, reduced", route: "wind-down", extra: ["-mockWindDown", "running:0.5:reduce"],
                ready: "windDown.screen"),
            pushed(
                "night.breathing.prestart", "Breathing, before starting", route: "tonight", extra: ["-mockBreathing", "prestart"], ready: "breathing.panel",
                steps: [.tapLabel("Breathing")]
            ),
            pushed(
                "night.breathing.running", "Breathing, running", route: "tonight", extra: ["-mockBreathing", "running:calm:5"], ready: "breathing.panel",
                steps: [.tapLabel("Breathing")]
            ),
            pushed(
                "night.breathing.finished", "Breathing, finished", route: "tonight", extra: ["-mockBreathing", "finished"], ready: "breathing.panel",
                steps: [.tapLabel("Breathing")]
            ),
            pushed(
                "night.meditation.prestart", "Meditation, before starting", route: "wind-down",
                extra: ["-mockWindDown", "running:0.2:meditation", "-mockMeditation", "prestart"],
                ready: "meditation.panel"
            ),
            pushed(
                "night.meditation.running", "Meditation, running", route: "wind-down",
                extra: ["-mockWindDown", "running:0.2:meditation", "-mockMeditation", "running:bodyScan:10:80"],
                ready: "meditation.panel"
            ),
            pushed(
                "night.meditation.finished", "Meditation, finished", route: "wind-down",
                extra: ["-mockWindDown", "running:0.2:meditation", "-mockMeditation", "finished"],
                ready: "meditation.panel"
            ),
            pushed(
                "night.reflect.empty", "Reflect, empty", route: "tonight", extra: ["-mockJournal", "empty"], ready: "reflect.panel",
                steps: [.tapLabel("Reflect")]
            ),
            pushed(
                "night.reflect.draft", "Reflect, a draft", route: "tonight", extra: ["-mockJournal", "empty:draft"], ready: "reflect.panel",
                steps: [.tapLabel("Reflect")]
            ),
            pushed(
                "night.journal.filled", "Journal with entries", route: "tonight", extra: ["-mockJournal", "filled:journal"], steps: [.tapLabel("Reflect")]
            ),
            pushed(
                "night.journal.empty", "Journal, empty", route: "tonight", extra: ["-mockJournal", "empty:journal"], steps: [.tapLabel("Reflect")]
            ),
            pushed(
                "night.journal.unavailable", "Journal, unavailable", route: "tonight", extra: ["-mockJournal", "unavailable:journal"],
                steps: [.tapLabel("Reflect")]
            ),
        ]
    }()

    // MARK: Reviews

    static let reviews: [CatalogScreen] = {
        let seeded = base() + ["-seedReviews"]
        var list: [CatalogScreen] = [
            CatalogScreen(
                id: "reviews.list", area: .reviews, title: "Reviews", arguments: seeded + ["-noctisInitialRoute", "insights"], route: "insights",
                opens: "reviews",
                // The seeded reviews are made at launch, after the list could have loaded: open the list from Insights once they exist.
                steps: [.wait(10), .tapLabelPrefix("Reviews"), .waitFor("reviews.list")], ready: "reviews.list", surface: .pushed
            ),
            CatalogScreen(
                id: "reviews.list.free", area: .reviews, title: "Reviews, free plan",
                arguments: seeded + ["-forceTier", "free", "-noctisInitialRoute", "insights"],
                route: "insights", opens: "reviews", steps: [.wait(10), .tapLabelPrefix("Reviews"), .waitFor("reviews.list")], ready: "reviews.list",
                surface: .pushed
            ),
        ]
        for page in ["cover", "sleep", "consistency", "recovery", "changes", "insight", "focus"] {
            list.append(
                CatalogScreen(
                    id: "reviews.weekly.\(page)", area: .reviews, title: "Weekly review: \(page)",
                    arguments: seeded + ["-reviewPage", page, "-noctisInitialRoute", "review:weekly"], route: "review:weekly", surface: .fullScreen
                )
            )
        }
        for page in ["cover", "sleepPattern", "recoveryPattern", "timing", "majorChanges", "insights", "records"] {
            list.append(
                CatalogScreen(
                    id: "reviews.monthly.\(page)", area: .reviews, title: "Monthly review: \(page)",
                    arguments: seeded + ["-reviewPage", page, "-noctisInitialRoute", "review:monthly"], route: "review:monthly", surface: .fullScreen
                )
            )
        }
        list.append(
            CatalogScreen(
                id: "reviews.monthly.locked", area: .reviews, title: "Monthly review, free plan",
                arguments: seeded + ["-forceTier", "free", "-noctisInitialRoute", "review:monthly"], route: "review:monthly", surface: .fullScreen
            )
        )
        return list
    }()

    // MARK: Premium

    static let premium: [CatalogScreen] = {
        var list: [CatalogScreen] = [
            CatalogScreen(
                id: "premium.paywall.trialEligible", area: .premium, title: "Paywall from a lock, a first-time user (intro offer eligible)",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general", "-introEligible", "yes"], surface: .sheet, needsStore: true
            ),
            CatalogScreen(
                id: "premium.paywall.trialNotEligible", area: .premium, title: "Paywall from a lock, not eligible for the intro offer",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general", "-introEligible", "no"], surface: .sheet, needsStore: true
            ),
            CatalogScreen(
                id: "onboarding.paywall.trialEligible", area: .onboarding, title: "Onboarding paywall, a first-time user (intro offer eligible)",
                arguments: ["-useMockHealth", "-noctis.onboarding.step", "paywall", "-introEligible", "yes"], surface: .fullScreen, showsOnboarding: true,
                needsStore: true
            ),
            CatalogScreen(
                id: "onboarding.paywall.trialNotEligible", area: .onboarding, title: "Onboarding paywall, not eligible for the intro offer",
                arguments: ["-useMockHealth", "-noctis.onboarding.step", "paywall", "-introEligible", "no"], surface: .fullScreen, showsOnboarding: true,
                needsStore: true
            ),
            CatalogScreen(
                id: "premium.paywall.loaded", area: .premium, title: "Paywall, with the plans loaded",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general"], surface: .sheet,
                tierOne: true, needsStore: true
            ),
            CatalogScreen(
                id: "premium.paywall.loading", area: .premium, title: "Paywall, plans loading",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general", "-mockStoreLoad", "loading"], surface: .sheet, tierOne: true
            ),
            CatalogScreen(
                id: "premium.paywall.unavailable", area: .premium, title: "Paywall, store unavailable",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general", "-mockStoreLoad", "unavailable"], surface: .sheet, tierOne: true
            ),
            CatalogScreen(
                id: "premium.compare", area: .premium, title: "Compare plans sheet",
                arguments: base() + ["-forceTier", "free", "-paywallContext", "general"], steps: [.tapLabel("Compare free and Premium")],
                ready: "premium.compare.done",
                surface: .sheet, needsStore: true
            ),
        ]
        for context in ["recovery30D", "sleepMonth", "coachQuestions", "windDown", "weeklyReview"] {
            list.append(
                CatalogScreen(
                    id: "premium.paywall.\(context)", area: .premium, title: "Paywall from \(context)",
                    arguments: base() + ["-forceTier", "free", "-paywallContext", context], surface: .sheet, needsStore: true
                )
            )
        }
        return list
    }()

    // MARK: Profile, Settings and privacy

    static let profile: [CatalogScreen] = [
        CatalogScreen(
            id: "profile.screen", area: .profile, title: "Profile", arguments: base() + ["-noctisInitialRoute", "profile"], route: "profile",
            ready: "profile.screen", surface: .pushed),
        CatalogScreen(
            id: "profile.screen.learning", area: .profile, title: "Profile while learning",
            arguments: base(scenario: "learning") + ["-noctisInitialRoute", "profile"],
            route: "profile", ready: "profile.screen", surface: .pushed
        ),
        CatalogScreen(
            id: "profile.editor.need", area: .profile, title: "Profile: sleep need editor", arguments: base() + ["-noctisInitialRoute", "profile"],
            route: "profile",
            steps: [.tapLabelPrefix("Sleep need")], ready: "profile.editor.need", surface: .sheet, scrolls: false
        ),
        CatalogScreen(
            id: "profile.editor.wake", area: .profile, title: "Profile: wake time editor", arguments: base() + ["-noctisInitialRoute", "profile"],
            route: "profile",
            steps: [.tapLabelPrefix("Wake time")], ready: "profile.editor.wake", surface: .sheet, scrolls: false
        ),
        CatalogScreen(
            id: "profile.editor.name", area: .profile, title: "Profile: name editor", arguments: base() + ["-noctisInitialRoute", "profile"], route: "profile",
            steps: [.tapIdentifier("profile.name")], ready: "profile.editor.name", surface: .sheet, scrolls: false
        ),
        CatalogScreen(
            id: "profile.editor.goals", area: .profile, title: "Profile: goals editor", arguments: base() + ["-noctisInitialRoute", "profile"],
            route: "profile",
            steps: [.tapLabelPrefix("Goals")], ready: "profile.editor.goals", surface: .sheet, scrolls: false
        ),
    ]

    static let settings: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for page in [
            "root", "notifications", "health-data", "appearance", "subscription", "wind-down", "sounds", "help", "about", "privacy-center", "data-management",
            "apple-watch",
        ] {
            let route = page == "root" ? "settings" : "settings:\(page)"
            list.append(
                CatalogScreen(
                    id: "settings.\(page)", area: page == "privacy-center" || page == "data-management" ? .privacy : .settings, title: "Settings: \(page)",
                    arguments: base() + [
                        "-mockNotifications", "granted", "-mockSubscription", "monthly", "-mockWatch", "connected", "-noctisInitialRoute", route,
                    ],
                    route: route, surface: .pushed, tierOne: page == "root"
                )
            )
        }
        list.append(
            CatalogScreen(
                id: "settings.subscription.free", area: .settings, title: "Settings: subscription, free",
                arguments: base() + ["-forceTier", "free", "-noctisInitialRoute", "settings:subscription"],
                route: "settings:subscription", surface: .pushed
            )
        )
        list.append(
            CatalogScreen(
                id: "settings.notifications.denied", area: .settings, title: "Settings: notifications, denied",
                arguments: base() + ["-mockNotifications", "denied", "-noctisInitialRoute", "settings:notifications"], route: "settings:notifications",
                surface: .pushed
            )
        )
        list.append(
            CatalogScreen(
                id: "settings.health-data.unauthorized", area: .settings, title: "Settings: Health data, no access",
                arguments: base() + ["-mockUnauthorized", "-noctisInitialRoute", "settings:health-data"], route: "settings:health-data", surface: .pushed
            )
        )
        list.append(
            CatalogScreen(
                id: "privacy.deleteAll", area: .privacy, title: "Delete all NOCTIS data, sheet",
                arguments: base() + ["-noctisInitialRoute", "settings:data-management"],
                route: "settings:data-management", steps: [.tapIdentifier("data.deleteAll")], ready: "data.deleteAll.sheet", surface: .sheet
            )
        )
        // Every confirmation Data management asks before it deletes or resets: one per row (QA part 4, tier 1).
        // A row's own identifier hides its button's, so the button is found by its label: the verb and the title.
        let groups: [(String, String)] = [
            ("journal", "Delete Journal"), ("coach", "Delete Coach history"), ("insights", "Delete Insights history"), ("reviews", "Delete Reviews"),
            ("windDown", "Delete Wind-down history"), ("cache", "Delete Cached summaries"), ("preferences", "Reset Preferences and goals"),
            ("setAside", "Delete Files set aside"),
        ]
        for (group, label) in groups {
            list.append(
                CatalogScreen(
                    id: "privacy.delete.\(group)", area: .privacy, title: "Data management: confirm \(group)",
                    arguments: base() + ["-noctisInitialRoute", "settings:data-management"],
                    route: "settings:data-management", steps: [.tapLabel(label), .wait(1.5)], ready: nil, surface: .sheet, scrolls: false
                )
            )
        }
        return list
    }()

    // MARK: Widgets and the Apple Watch

    static let widgets: [CatalogScreen] = [
        CatalogScreen(
            id: "widgets.gallery.premium", area: .widgets, title: "Widget gallery, Premium", arguments: ["-widgetGallery", "-widgetGalleryTier", "premium"],
            ready: "widgetGallery", surface: .gallery, tierOne: false
        ),
        CatalogScreen(
            id: "widgets.gallery.free", area: .widgets, title: "Widget gallery, free", arguments: ["-widgetGallery", "-widgetGalleryTier", "free"],
            ready: "widgetGallery",
            surface: .gallery
        ),
        CatalogScreen(
            id: "widgets.gallery.dark", area: .widgets, title: "Widget gallery, dark", arguments: ["-widgetGallery", "-widgetGalleryAppearance", "dark"],
            ready: "widgetGallery",
            surface: .gallery
        ),
        CatalogScreen(
            id: "widgets.gallery.accented", area: .widgets, title: "Widget gallery, accented",
            arguments: ["-widgetGallery", "-widgetGalleryAppearance", "accented"],
            ready: "widgetGallery", surface: .gallery
        ),
    ]

    static let watch: [CatalogScreen] = {
        var list: [CatalogScreen] = []
        for page in ["recovery", "sleep", "heart", "tonight", "settings"] {
            list.append(
                CatalogScreen(
                    id: "watch.page.\(page)", area: .watch, title: "Apple Watch: \(page)", arguments: ["-watchMockSnapshot", "full", "-watchPage", page],
                    surface: .fullScreen,
                    platform: .watch, scrolls: false
                )
            )
        }
        for state in ["learning", "sleepOnly", "empty", "stale", "gap", "waiting", "noSnapshot"] {
            list.append(
                CatalogScreen(
                    id: "watch.state.\(state)", area: .watch, title: "Apple Watch, \(state)", arguments: ["-watchMockSnapshot", state], surface: .fullScreen,
                    platform: .watch, scrolls: false
                )
            )
        }
        for script in ["picker", "running:calm:5:30", "done"] {
            list.append(
                CatalogScreen(
                    id: "watch.breathing.\(script.split(separator: ":").first ?? "")", area: .watch, title: "Apple Watch breathing: \(script)",
                    arguments: ["-watchMockSnapshot", "full", "-watchBreathing", script], surface: .fullScreen, platform: .watch, scrolls: false
                )
            )
        }
        for face in ["recovery", "sleep", "bedtime", "quality"] {
            list.append(
                CatalogScreen(
                    id: "watch.complication.\(face)", area: .watch, title: "Complications: \(face)", arguments: ["-complicationGallery", face],
                    surface: .gallery, platform: .watch, scrolls: false
                )
            )
        }
        return list
    }()

    /// Every entry, in the order QA_COVERAGE.md lists them.
    public static let all: [CatalogScreen] =
        onboarding + home + sleep + recovery + insights + coach + night + reviews + premium + profile + settings + widgets + watch

    public static var iPhone: [CatalogScreen] { all.filter { $0.platform == .iPhone } }
}
