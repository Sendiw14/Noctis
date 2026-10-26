import Foundation

/// The numbers "Find help" shows, built in so the list works with no network (QA part 6). A region is an ISO 3166 code ("LK"); a person's region
/// comes from the device's locale and can be changed in the sheet. Each entry is a public emergency or crisis line the country itself runs or names.
/// OWNER REVIEW (QA_REPORT.md section 5): a person must check every number against its operator before release; numbers change, and the sheet
/// always also links findahelpline.com (worldwide, by country) and says to call the local emergency number first.
public nonisolated struct CoachHelpline: Sendable, Equatable, Identifiable {
    public let name: String
    /// Digits as dialled, with spaces for reading.
    public let number: String
    public var id: String { name + number }
    /// `tel:` needs the digits only.
    public var dialURL: URL? { URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" }) }
}

public nonisolated struct CoachHelpRegion: Sendable, Equatable, Identifiable {
    public let code: String
    public let name: String
    public let emergency: CoachHelpline
    public let lines: [CoachHelpline]
    public var id: String { code }
}

public nonisolated enum CoachHelplines {
    private static func line(_ name: String, _ number: String) -> CoachHelpline { CoachHelpline(name: name, number: number) }

    public static let regions: [CoachHelpRegion] = [
        CoachHelpRegion(
            code: "LK", name: "Sri Lanka", emergency: line("Police emergency", "119"),
            lines: [
                line("Ambulance (Suwa Seriya)", "1990"), line("National Mental Health Helpline", "1926"), line("Sumithrayo (emotional support)", "011 2682535"),
            ]),
        CoachHelpRegion(code: "US", name: "United States", emergency: line("Emergency", "911"), lines: [line("988 Suicide & Crisis Lifeline", "988")]),
        CoachHelpRegion(code: "CA", name: "Canada", emergency: line("Emergency", "911"), lines: [line("9-8-8 Suicide Crisis Helpline", "988")]),
        CoachHelpRegion(
            code: "GB", name: "United Kingdom", emergency: line("Emergency", "999"),
            lines: [line("Samaritans", "116 123"), line("NHS urgent mental health help", "111")]),
        CoachHelpRegion(code: "IE", name: "Ireland", emergency: line("Emergency", "112"), lines: [line("Samaritans", "116 123")]),
        CoachHelpRegion(code: "AU", name: "Australia", emergency: line("Emergency", "000"), lines: [line("Lifeline", "13 11 14")]),
        CoachHelpRegion(code: "NZ", name: "New Zealand", emergency: line("Emergency", "111"), lines: [line("Need to talk? (call or text)", "1737")]),
        CoachHelpRegion(code: "IN", name: "India", emergency: line("Emergency", "112"), lines: [line("Tele-MANAS", "14416")]),
    ]

    /// Shown when the region has no list of its own, or none is known: the number that reaches emergency services across the EU and most mobile
    /// networks, and the worldwide directory.
    public static let generic = CoachHelpRegion(
        code: "", name: "Another country", emergency: line("Emergency (most mobile networks)", "112"),
        lines: [line("Your local emergency number", "112")]
    )

    public static let directoryURL = URL(string: "https://findahelpline.com")

    /// The region's list, or `generic`.
    public static func region(for code: String?) -> CoachHelpRegion {
        guard let code = code?.uppercased() else { return generic }
        return regions.first { $0.code == code } ?? generic
    }

    public static func region(for locale: Locale) -> CoachHelpRegion { region(for: locale.region?.identifier) }
}
