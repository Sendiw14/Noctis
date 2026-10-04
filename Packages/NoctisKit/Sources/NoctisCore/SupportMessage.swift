import Foundation

/// The message "Contact support" starts: an address, a subject, and a body that holds the app's version, its
/// build and the iOS version, and nothing else. No profile, no Health data, no identifiers.
public nonisolated enum SupportMessage {
    public static let subject = "NOCTIS support"

    /// A blank first line for the person's own words, then the three facts.
    public static func body(version: String, build: String, iOS: String) -> String {
        "\n\n\u{2014}\nNOCTIS \(version) (\(build))\niOS \(iOS)"
    }

    /// The `mailto:` link, for a phone with no Mail composer set up.
    public static func mailtoURL(address: String = StoreLegalLinks.supportEmail, version: String, build: String, iOS: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(version: version, build: build, iOS: iOS)),
        ]
        return components.url
    }
}

/// The Language row (Settings opens the app's own page in the system's Settings, where the person picks the app's
/// language): offered only when the app has more than one language to choose from (APP_RULES.md R36).
public nonisolated enum LanguageRow {
    /// `localizations` is `Bundle.main.localizations`; "Base" is not a language.
    public static func isOffered(localizations: [String]) -> Bool {
        languages(in: localizations).count > 1
    }

    public static func languages(in localizations: [String]) -> [String] {
        var seen: [String] = []
        for code in localizations where code != "Base" && !seen.contains(code) { seen.append(code) }
        return seen
    }

    /// The name of the language the app is showing, in that language ("Français"); nil when it can't be named.
    public static func currentName(preferred: [String], available: [String], locale: Locale = .autoupdatingCurrent) -> String? {
        let languages = languages(in: available)
        guard !languages.isEmpty, let match = Bundle.preferredLocalizations(from: languages, forPreferences: preferred).first else { return nil }
        let own = Locale(identifier: match)
        return own.localizedString(forIdentifier: match)?.localizedCapitalized ?? locale.localizedString(forIdentifier: match)
    }
}
