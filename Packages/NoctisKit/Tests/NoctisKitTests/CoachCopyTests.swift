import Foundation
import Testing
@testable import CoachKit

struct CoachCopyTests {
    @Test func theCatalogIsInTheBundleAndReadable() {
        #expect(CoachCopy.string("coach.footer") == "Coach shares patterns from your data. It isn't medical advice.")
        #expect(CoachCopy.string("coach.script.unknown") == "I can help with questions about your sleep and recovery.")
        #expect(CoachCopy.string("coach.missing.key") == "coach.missing.key", "a missing key shows itself")
    }
}
