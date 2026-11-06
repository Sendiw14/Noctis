import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

// Button Shapes (S1B-A01, UX-02): a text-only button carries a rule under its words when the setting is on, and is drawn exactly as before when it is off.

@MainActor
struct ButtonShapeTests {
    /// The label as a button draws it: text first, the modifier on it, then padding and a frame.
    private func label(_ title: String, width: CGFloat, color: Color, _ shapes: Bool?) -> some View {
        let text = Text(title).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(color)
        return Group {
            if let shapes { text.modifier(NoctisButtonShape(showsShapes: shapes)).frame(width: width) } else { text.frame(width: width) }
        }
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func image(title: String = "Restore", width: CGFloat = 120, color: Color = .black, shapes: Bool?) throws -> UIImage {
        let renderer = ImageRenderer(content: label(title, width: width, color: color, shapes))
        renderer.scale = 2
        return try #require(renderer.uiImage)
    }

    /// Pixels that are dark (a black rule over a coloured label would show up here).
    private func darkPixels(_ image: UIImage) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        let step = cg.bitsPerPixel / 8
        var count = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let o = y * cg.bytesPerRow + x * step
                if bytes[o] < 110 && bytes[o + 1] < 110 && bytes[o + 2] < 110 { count += 1 }
            }
        }
        return count
    }

    private func ink(_ image: UIImage, rowsFrom top: Double = 0) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        let step = cg.bitsPerPixel / 8
        var count = 0
        for y in Int(Double(cg.height) * top)..<cg.height {
            for x in 0..<cg.width {
                let o = y * cg.bytesPerRow + x * step
                if bytes[o] < 200 || bytes[o + 1] < 200 || bytes[o + 2] < 200 { count += 1 }
            }
        }
        return count
    }

    @Test func withTheSettingOffNothingIsDrawn() throws {
        #expect(try image(shapes: false).pngData() == image(shapes: nil).pngData(), "pixel for pixel the same as a label with no modifier")
        #expect(try image(title: "A longer label that wraps over two lines", width: 90, shapes: false).pngData() == image(title: "A longer label that wraps over two lines", width: 90, shapes: nil).pngData())
    }

    @Test func withTheSettingOnTheWordsAreUnderlined() throws {
        #expect(try image(shapes: true).pngData() != image(shapes: false).pngData())
        #expect(try ink(image(shapes: true)) > ink(image(shapes: false)), "more ink: the underline")
    }

    @Test func theUnderlineTakesTheColourOfTheText() throws {
        let red = try image(color: .red, shapes: true)
        #expect(darkPixels(red) == 0, "no black anywhere: a red label has a red underline, not a separate black rule")
        let black = try image(color: .black, shapes: true)
        #expect(darkPixels(black) > 0, "the control: a black label does have dark pixels, so the check can see them")
    }

    @Test func aWrappedLabelIsUnderlinedLineByLineNotWithOneFullWidthRule() throws {
        let title = "Continue with the free plan and decide later"
        let one = try image(title: title, width: 400, shapes: true)
        let wrapped = try image(title: title, width: 110, shapes: true)
        let plainWrapped = try image(title: title, width: 110, shapes: false)
        #expect(ink(wrapped) > ink(plainWrapped) + 100, "every wrapped line gets its own underline")
        // The underline sits inside the label: the rows below the last line are as empty as with the setting off.
        #expect(ink(wrapped, rowsFrom: 0.93) == ink(plainWrapped, rowsFrom: 0.93), "nothing is drawn below the text")
        #expect(one.size.height < wrapped.size.height)
    }

    @Test func aLabelIsNotClippedByItsPadding() throws {
        let on = try image(shapes: true)
        let off = try image(shapes: false)
        #expect(on.size == off.size, "the underline does not change the size of the label")
    }

    @Test func theTextButtonAndTheTextLinksUseIt() throws {
        let root = RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources")
        for (path, count) in [
            ("DesignSystem/NoctisCTA.swift", 1), ("DesignSystem/OnboardingStepScaffold.swift", 1), ("OnboardingFeature/PaywallScreen.swift", 2),
            ("NightFeature/WindDownScreen.swift", 1),
        ] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(text.components(separatedBy: ".noctisButtonShape()").count - 1 >= count, Comment(rawValue: path))
        }
    }

    @Test func theSystemsOwnShapedButtonsAreNotShapedTwice() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/OnboardingFeature/PaywallScreen.swift"), encoding: .utf8)
        let link = try #require(text.range(of: "private func linkLabel(_ title: String)"))
        #expect(!text[link.upperBound...].prefix(400).contains("noctisButtonShape"), "Restore Purchases, Terms and Privacy are system buttons: the system draws their shape")
    }

    @Test func theSettingIsReadFromTheSystemNotFromTheProbeOnly() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/DesignSystem/NoctisButtonShape.swift"), encoding: .utf8)
        #expect(text.contains("accessibilityShowButtonShapes"))
    }
}

// Smart Invert (S1B-A03, UX-02): a rendered picture is not re-inverted by the system.
struct SmartInvertTests {
    @Test func everyViewThatShowsARenderedPictureOptsOutOfInversion() {
        let files = RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "Widgets", "Watch"])
        #expect(!files.isEmpty)
        for file in files where RawDefaultsTests.code(file.text).contains("Image(uiImage:") {
            #expect(RawDefaultsTests.code(file.text).contains("accessibilityIgnoresInvertColors"), Comment(rawValue: "\(file.path) shows a picture"))
        }
    }
}
