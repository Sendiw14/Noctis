import QACatalog
import StoreKitTest
import UIKit
import XCTest

/// QA part 3 (QA_COVERAGE.md 3.7, APP_RULES.md R67): the accessibility audit of every screen in the catalog.
///
/// For each screen: Xcode's own `performAccessibilityAudit(for: .all)` with every issue recorded, not failed (the triage is the ledger's: a real
/// failure is fixed, a false positive is documented with why); a measured contrast ratio for every contrast issue (the rendered pixels of the
/// element's frame, the most common color against the one that differs most, as WCAG's ratio) with the crop saved beside it; and the order a
/// screen reader takes the elements in against the order they are drawn in.
///
/// Output under `<QA_OUT>/audit/<QA_CONFIG>/<device>/`: `<screen id>__audit.tsv` (one issue per line), `<screen id>__order.txt`, the crops, and
/// `summary.jsonl`. Environment as for QAMatrixTests (`QA_OUT`, `QA_CONFIG`, `QA_ONLY`, `QA_TIER1`, `QA_LAUNCH_EXTRA`, `QA_RESUME`).
@MainActor
final class AuditQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private var environment: [String: String] { QA.environment }
    private var configuration: String { environment["QA_CONFIG"] ?? "default" }
    /// The folder's name for the device: `QA_DEVICE_NAME` when a second simulator of the same model shares the work, else the simulator's own name.
    private var device: String { (environment["QA_DEVICE_NAME"] ?? environment["SIMULATOR_DEVICE_NAME"] ?? "device").replacingOccurrences(of: " ", with: "") }
    private var extraLaunch: [String] { (environment["QA_LAUNCH_EXTRA"] ?? "").split(separator: " ").map(String.init) }

    private var outputDirectory: URL {
        let url = URL(fileURLWithPath: environment["QA_OUT"] ?? NSTemporaryDirectory())
            .appendingPathComponent("audit", isDirectory: true)
            .appendingPathComponent(configuration, isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func selected() -> [CatalogScreen] {
        let only = (environment["QA_ONLY"] ?? "").split(separator: ",").map(String.init)
        return ScreenCatalog.iPhone.filter { screen in
            if screen.surface == .gallery { return false }
            if environment["QA_TIER1"] == "1", !screen.tierOne { return false }
            return only.isEmpty || only.contains { screen.id.hasPrefix($0) }
        }
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: Reaching the screen

    /// Lives for the visit: the plans a paywall shows come from `Noctis.storekit` through this session.
    private var store: SKTestSession?

    private func reach(_ screen: CatalogScreen) -> XCUIApplication {
        store = nil
        if screen.needsStore {
            let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Config/Noctis.storekit")
            store = try? SKTestSession(contentsOf: file)
            store?.disableDialogs = true
            store?.resetToDefaultState()
        }
        let app = QA.launch(extra: screen.arguments + ["-noctisEnvironmentProbe"] + extraLaunch)
        if let identifier = screen.ready { _ = element(app, identifier).waitForExistence(timeout: 20) } else { QA.pause(4.5) }
        for step in screen.steps {
            switch step {
            case .tapTab(let label): app.tabBars.buttons[label].tap()
            case .tapLabel(let label): QA.button(app, label).tap()
            case .tapLabelPrefix(let prefix):
                let target = QA.element(app, labelBeginsWith: prefix)
                if target.waitForExistence(timeout: 10) { target.tap() }
            case .tapIdentifier(let identifier):
                let target = element(app, identifier)
                if target.waitForExistence(timeout: 10) { target.tap() }
            case .scrollToTop:
                for _ in 0..<6 { app.swipeDown() }
            case .waitFor(let identifier): _ = element(app, identifier).waitForExistence(timeout: 20)
            case .waitForPrefix(let prefix):
                _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.waitForExistence(timeout: 20)
            case .back: app.navigationBars.buttons.firstMatch.tap()
            case .type(let text):
                let field = app.textFields.firstMatch
                if field.waitForExistence(timeout: 10) {
                    field.tap()
                    field.typeText(text)
                }
            case .wait(let seconds): QA.pause(seconds)
            }
            QA.pause(1.0)
        }
        if let identifier = screen.ready, !screen.steps.isEmpty { _ = element(app, identifier).waitForExistence(timeout: 20) }
        QA.pause(1.0)
        return app
    }

    // MARK: Contrast, measured from the rendered pixels

    /// The WCAG contrast ratio of `image`'s dominant color against the color that differs most from it (the text over its background), or nil
    /// when the crop has one color only.
    private func contrastRatio(of image: CGImage) -> (ratio: Double, foreground: String, background: String)? {
        let width = min(image.width, 400), height = min(image.height, 200)
        guard width > 1, height > 1 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var counts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            // Quantized to 5 bits a channel so anti-aliasing noise does not split the background.
            let key = UInt32(pixels[index] >> 3) << 10 | UInt32(pixels[index + 1] >> 3) << 5 | UInt32(pixels[index + 2] >> 3)
            counts[key, default: 0] += 1
        }
        guard let backgroundKey = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        func channels(_ key: UInt32) -> (Double, Double, Double) {
            (Double((key >> 10) & 31) * 8 + 4, Double((key >> 5) & 31) * 8 + 4, Double(key & 31) * 8 + 4)
        }
        let background = channels(backgroundKey)
        // The foreground: the most distant color that covers at least 0.4% of the crop (a glyph's core, not one anti-aliased pixel).
        let floor = max(3, pixels.count / 4 / 250)
        let candidates = counts.filter { $0.value >= floor && $0.key != backgroundKey }
        func distance(_ key: UInt32) -> Double {
            let c = channels(key)
            return pow(c.0 - background.0, 2) + pow(c.1 - background.1, 2) + pow(c.2 - background.2, 2)
        }
        guard let foregroundKey = candidates.max(by: { distance($0.key) < distance($1.key) })?.key else { return nil }
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func linear(_ v: Double) -> Double {
                let s = v / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
        }
        let fg = channels(foregroundKey)
        let l1 = luminance(fg), l2 = luminance(background)
        let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        func hex(_ c: (Double, Double, Double)) -> String { String(format: "#%02X%02X%02X", Int(c.0), Int(c.1), Int(c.2)) }
        return (ratio, hex(fg), hex(background))
    }

    // MARK: One screen

    private func audit(_ screen: CatalogScreen) {
        let directory = outputDirectory
        if environment["QA_RESUME"] == "1", FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__audit.tsv").path) { return }
        let app = reach(screen)
        defer { app.terminate() }
        let full = XCUIScreen.main.screenshot()
        let windowWidth = max(app.windows.firstMatch.frame.width, 1)
        try? full.pngRepresentation.write(to: directory.appendingPathComponent("\(screen.id)__audited.png"))
        let cgImage = full.image.cgImage
        // Points to pixels: the screenshot's width over the window's.
        let scale = cgImage.map { CGFloat($0.width) / windowWidth } ?? 1

        // The structural checks, at the top of the page (QAMatrixTests runs them at both ends under every configuration).
        let hierarchy = QA.hierarchyChecks(app, at: "top")
        try? (hierarchy.isEmpty ? "none" : hierarchy.joined(separator: "\n")).write(
            to: directory.appendingPathComponent("\(screen.id)__hierarchy.txt"), atomically: true, encoding: .utf8)

        var lines: [String] = []
        var index = 0
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                index += 1
                let element = issue.element
                let frame = element?.frame ?? .zero
                var measured = ""
                if issue.auditType == .contrast, let cgImage, frame.width > 1, frame.height > 1 {
                    let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
                        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                    if !rect.isEmpty, let crop = cgImage.cropping(to: rect) {
                        let name = "\(screen.id)__contrast\(index).png"
                        if let data = UIImage(cgImage: crop).pngData() { try? data.write(to: directory.appendingPathComponent(name)) }
                        if let result = self.contrastRatio(of: crop) {
                            measured = String(format: "%.2f:1 %@ on %@ %@", result.ratio, result.foreground, result.background, name)
                        } else {
                            measured = "one color only \(name)"
                        }
                    }
                }
                let label = (element?.label ?? "-").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                let identifier = element?.identifier ?? "-"
                let type = element.map { String($0.elementType.rawValue) } ?? "-"
                let row = [
                    "\(issue.auditType.rawValue)", issue.compactDescription, issue.detailedDescription.replacingOccurrences(of: "\n", with: " "),
                    label, identifier, type, NSCoder.string(for: frame), measured,
                ]
                lines.append(row.joined(separator: "\t"))
                // Recorded, not failed: the triage decides (QA_COVERAGE.md).
                return true
            }
        } catch {
            lines.append("-1\tthe audit itself failed\t\(error.localizedDescription)\t-\t-\t-\t-\t")
        }
        try? (lines.isEmpty ? "none" : lines.joined(separator: "\n")).write(
            to: directory.appendingPathComponent("\(screen.id)__audit.tsv"), atomically: true, encoding: .utf8)

        // The order a screen reader takes against the order the elements are drawn in.
        var order: [String] = []
        if let snapshot = try? app.snapshot() {
            var leaves: [XCUIElementSnapshot] = []
            func walk(_ node: XCUIElementSnapshot) {
                if node.children.isEmpty { leaves.append(node) }
                node.children.forEach(walk)
            }
            walk(snapshot)
            let window = app.windows.firstMatch.frame
            let visible = leaves.filter { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.intersects(window) && !$0.label.isEmpty }
            var previous: XCUIElementSnapshot?
            var jumps = 0
            for leaf in visible {
                if let previous, leaf.frame.minY < previous.frame.minY - 12 {
                    jumps += 1
                    order.append(
                        "goes back up: '\(previous.label.prefix(40))' (y \(Int(previous.frame.minY))) is followed by '\(leaf.label.prefix(40))' (y \(Int(leaf.frame.minY)))"
                    )
                }
                previous = leaf
            }
            // Voice Control says "tap <name>": two controls with the same name on one screen cannot be told apart by it.
            let controls: Set<XCUIElement.ElementType> = [.button, .link, .switch, .toggle, .slider, .stepper, .textField, .segmentedControl, .tab]
            var byName: [String: Int] = [:]
            for leaf in visible where controls.contains(leaf.elementType) { byName[leaf.label, default: 0] += 1 }
            let duplicates = byName.filter { $0.value > 1 }.sorted { $0.key < $1.key }
            for (name, count) in duplicates { order.append("voice control: \(count) controls are named '\(name.prefix(60))'") }
            order.insert(
                "\(visible.count) elements, \(jumps) places where the reading order goes back up the screen, \(duplicates.count) control names used more than once",
                at: 0)
            order.append("-- in reading order:")
            order += visible.map { "\(Int($0.frame.minY)),\(Int($0.frame.minX)) \($0.elementType.rawValue) \($0.label.prefix(60))" }
        }
        try? order.joined(separator: "\n").write(to: directory.appendingPathComponent("\(screen.id)__order.txt"), atomically: true, encoding: .utf8)

        let summary =
            "{\"id\":\"\(screen.id)\",\"config\":\"\(configuration)\",\"device\":\"\(device)\",\"issues\":\(lines.filter { !$0.hasPrefix("-1") }.count)}\n"
        if let handle = try? FileHandle(forWritingTo: directory.appendingPathComponent("summary.jsonl")) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(summary.utf8))
            try? handle.close()
        } else {
            try? summary.write(to: directory.appendingPathComponent("summary.jsonl"), atomically: true, encoding: .utf8)
        }
    }

    func testAuditEveryScreenInTheSelection() {
        for screen in selected() { audit(screen) }
    }
}
