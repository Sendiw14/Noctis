import Foundation

#if DEBUG
// QA part 3 (QA_COVERAGE.md 4, APP_RULES.md R68): `-pseudoScript si|ta` makes every unit and count NOCTIS prints come out as real Sinhala or Tamil words, so
// the clipping and the line height of those scripts (which are taller than Latin and wider than English) can be seen on a screen that has no translation yet.
// Metrics only: the sentences around them stay English. Real words, not a transliteration: "පැය" is an hour and "மணி" is an hour. DEBUG builds only.

enum NoctisPseudoScript {
    /// "si", "ta", or nil.
    static let current: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-pseudoScript"), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value == "si" || value == "ta" ? value : nil
    }()

    private static let words: [String: [String: String]] = [
        "si": [
            "pseudo.hour": "පැය", "pseudo.minute": "මිනිත්තු", "pseudo.second": "තත්පර", "pseudo.night": "රාත්‍රි", "pseudo.day": "දින", "pseudo.month": "මාස",
            "pseudo.year": "වසර",
            "pseudo.insight": "අවබෝධ", "pseudo.question": "ප්‍රශ්න", "pseudo.awakening": "අවදි වීම්", "pseudo.value": "අගය", "pseudo.reminder": "මතක් කිරීම්",
            "pseudo.point": "ලකුණු",
            "pseudo.percent": "ප්‍රතිශතය", "pseudo.beat": "හෘද ස්පන්දන", "pseudo.week": "සතියකට",
        ],
        "ta": [
            "pseudo.hour": "மணி நேரம்", "pseudo.minute": "நிமிடங்கள்", "pseudo.second": "வினாடிகள்", "pseudo.night": "இரவுகள்", "pseudo.day": "நாட்கள்",
            "pseudo.month": "மாதங்கள்", "pseudo.year": "ஆண்டுகள்",
            "pseudo.insight": "நுண்ணறிவுகள்", "pseudo.question": "கேள்விகள்", "pseudo.awakening": "விழிப்புகள்", "pseudo.value": "மதிப்புகள்", "pseudo.reminder": "நினைவூட்டல்கள்",
            "pseudo.point": "புள்ளிகள்", "pseudo.percent": "சதவீதம்", "pseudo.beat": "துடிப்புகள்", "pseudo.week": "வாரத்திற்கு",
        ],
    ]

    /// The word for a noun key ("hour", "night"…), in the script asked for.
    static func word(_ noun: String) -> String? {
        guard let current else { return nil }
        return words[current]?["pseudo.\(noun)"]
    }

    /// "8 மணி நேரம்": the number and the word.
    static func phrase(_ count: Int, _ noun: String, suffix: String = "") -> String? {
        word(noun).map { "\(count) \($0)\(suffix)" }
    }
}
#endif
