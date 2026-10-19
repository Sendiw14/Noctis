import Foundation
import Testing

@testable import CoachKit

// QA part 6: "Find help" is region-aware and built in: no network is involved in choosing or drawing the list.
struct CoachHelplinesTests {
    @Test func sriLankaHasItsOwnListAndNeverASingleOtherCountry() {
        let lk = CoachHelplines.region(for: Locale(identifier: "si_LK"))
        #expect(lk.code == "LK" && lk.name == "Sri Lanka")
        #expect(lk.emergency.number == "119")
        #expect(lk.lines.contains { $0.number == "1926" })
        #expect(CoachHelplines.region(for: "us").code == "US", "the code is case-insensitive")
    }

    @Test func aRegionWithNoListFallsBackToTheGenericOneNotToAnotherCountry() {
        #expect(CoachHelplines.region(for: "ZZ") == CoachHelplines.generic)
        #expect(CoachHelplines.region(for: nil) == CoachHelplines.generic)
        #expect(CoachHelplines.region(for: Locale(identifier: "en")) == CoachHelplines.generic)
        #expect(CoachHelplines.generic.emergency.number == "112")
    }

    @Test func everyEntryCanBeDialledAndRegionsAreUnique() {
        let all = CoachHelplines.regions + [CoachHelplines.generic]
        #expect(Set(CoachHelplines.regions.map(\.code)).count == CoachHelplines.regions.count)
        for region in all {
            for item in [region.emergency] + region.lines {
                #expect(item.dialURL?.scheme == "tel", Comment(rawValue: "\(region.code) \(item.name)"))
                #expect(item.number.contains { $0.isNumber } && !item.name.isEmpty)
            }
        }
        #expect(CoachHelplines.directoryURL?.host == "findahelpline.com")
    }
}
