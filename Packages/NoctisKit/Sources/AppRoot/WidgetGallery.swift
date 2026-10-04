#if DEBUG
import DesignSystem
import NoctisWidgetKit
import SwiftUI
import UIKit
import WidgetKit

// The DEBUG widget gallery (APP_RULES.md R45): `-widgetGallery [scenes] [-widgetGalleryAppearance light|dark|accented]`. Every family at
// its real size on an iPhone 17 Pro (402 x 874), in light, dark and an accented approximation, in every data state, so a screenshot
// can be taken of each. `-widgetGalleryExport` also writes each panel as a 3x PNG into the temporary folder's WidgetGallery.
//
// It is NOT the real thing. Real Home Screen and Lock Screen placement, the system's tinted and clear modes, and the redaction on a
// locked device have to be seen on an iPhone. The accented panels approximate the system's treatment (desaturated content over a
// dark backdrop); the locked panels apply `.redacted(reason: .privacy)`, which is how a widget is told it is on a locked screen.

public enum WidgetGalleryScene: String, CaseIterable, Identifiable {
    case day, evening, sleepOnly, learning, empty, stale, gap, waiting, noSnapshot, locked

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day, full data"
        case .evening: "Evening"
        case .sleepOnly: "Sleep only"
        case .learning: "Learning (3 of 5 nights)"
        case .empty: "Empty or no permission"
        case .stale: "Stale (14h)"
        case .gap: "No sleep last night"
        case .waiting: "Waiting (snapshot is for yesterday)"
        case .noSnapshot: "No snapshot yet"
        case .locked: "Locked (redacted)"
        }
    }

    /// 10:00 in the morning, or 21:30 in the evening, on today's date.
    func date(calendar: Calendar) -> Date {
        let hour = self == .evening ? 21 : 10
        return calendar.date(bySettingHour: hour, minute: self == .evening ? 30 : 0, second: 0, of: Date()) ?? Date()
    }

    func entry(calendar: Calendar) -> WidgetEntryModel {
        let now = date(calendar: calendar)
        let snapshot: WidgetSnapshot?
        switch self {
        case .day, .evening, .locked: snapshot = WidgetSamples.snapshot(.full, now: now, calendar: calendar)
        case .sleepOnly: snapshot = WidgetSamples.snapshot(.sleepOnly, now: now, calendar: calendar)
        case .learning: snapshot = WidgetSamples.snapshot(.learning(nightsSoFar: 3), now: now, calendar: calendar)
        case .empty: snapshot = WidgetSamples.snapshot(.noPermission, now: now, calendar: calendar)
        case .stale: snapshot = WidgetSamples.snapshot(.stale(hours: 14), now: now, calendar: calendar)
        case .gap: snapshot = WidgetSamples.snapshot(.gap, now: now, calendar: calendar)
        case .waiting:
            // A full snapshot, but for yesterday.
            var yesterday = WidgetSamples.snapshot(.full, now: now, calendar: calendar)
            yesterday.forDay = WidgetDay.today(at: now.addingTimeInterval(-86_400), calendar: calendar)
            snapshot = yesterday
        case .noSnapshot: snapshot = nil
        }
        // These are the gallery's samples, drawn as the real timeline would draw them (not tagged: the "Sample" tag is for the widget
        // gallery's own preview, which `WidgetGalleryAppearance` does not use).
        return WidgetTimelineBuilder.entry(for: snapshot, at: now, calendar: calendar)
    }
}

public enum WidgetGalleryAppearance: String, CaseIterable, Identifiable {
    case light, dark, accented

    public var id: String { rawValue }
    var scheme: ColorScheme { self == .light ? .light : .dark }
}

/// What the launch arguments asked for.
public struct WidgetGalleryRequest {
    public var scenes: [WidgetGalleryScene]
    public var appearances: [WidgetGalleryAppearance]
    public var exports: Bool

    public init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-widgetGallery") else { return nil }
        let value = arguments.indices.contains(flag + 1) && !arguments[flag + 1].hasPrefix("-") ? arguments[flag + 1] : "day"
        scenes = value == "all" ? WidgetGalleryScene.allCases : value.split(separator: ",").compactMap { WidgetGalleryScene(rawValue: String($0)) }
        let look = arguments.firstIndex(of: "-widgetGalleryAppearance").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        appearances = look == nil || look == "all" ? WidgetGalleryAppearance.allCases : look.flatMap(WidgetGalleryAppearance.init(rawValue:)).map { [$0] } ?? []
        exports = arguments.contains("-widgetGalleryExport")
        if scenes.isEmpty || appearances.isEmpty { return nil }
    }
}

// MARK: - A tile, at its real size

/// The real size of each family on an iPhone 17 Pro (402 x 874), in points.
enum WidgetGallerySize {
    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        default: CGSize(width: 257, height: 26)
        }
    }

    static let cornerRadius: CGFloat = 22
    /// The content margin the system gives a widget's content.
    static let margin: CGFloat = 16
}

struct WidgetGalleryTile: View {
    let family: WidgetFamily
    let entry: WidgetEntryModel
    let appearance: WidgetGalleryAppearance
    let locked: Bool

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }

    var body: some View {
        let size = WidgetGallerySize.size(family)
        Group {
            if isAccessory {
                NoctisLockWidgetView(entry: entry, family: family)
                    .padding(family == .accessoryInline ? 0 : 8)
                    .frame(width: size.width, height: size.height, alignment: family == .accessoryRectangular ? .leading : .center)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .background(accessoryBackground)
                    .environment(\.colorScheme, .dark)
                    .environment(\.widgetRenderingMode, appearance == .accented ? .accented : .vibrant)
            } else {
                NoctisTodayWidgetView(entry: entry, family: family)
                    .padding(WidgetGallerySize.margin)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .background { homeScreenBackground }
                    .clipShape(RoundedRectangle(cornerRadius: WidgetGallerySize.cornerRadius, style: .continuous))
                    .environment(\.widgetRenderingMode, appearance == .accented ? .accented : .fullColor)
                    .saturation(appearance == .accented ? 0 : 1)
            }
        }
        .redacted(reason: locked ? .privacy : [])
    }

    @ViewBuilder
    private var homeScreenBackground: some View {
        if appearance == .accented { Color.black.opacity(0.35) } else { WidgetBackground(mode: entry.mode) }
    }

    @ViewBuilder
    private var accessoryBackground: some View {
        switch family {
        case .accessoryCircular: Circle().fill(Color.white.opacity(0.18))
        case .accessoryRectangular: RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.18))
        default: Color.clear
        }
    }
}

// MARK: - A panel: every family for one scene in one appearance

struct WidgetGalleryPanel: View {
    let scene: WidgetGalleryScene
    let appearance: WidgetGalleryAppearance

    var body: some View {
        let entry = scene.entry(calendar: .autoupdatingCurrent)
        let locked = scene == .locked
        VStack(alignment: .leading, spacing: 12) {
            Text("\(scene.title) · \(appearance.rawValue)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(appearance == .light ? Color(red: 0.17, green: 0.11, blue: 0.08) : Color.white)
            HStack(alignment: .top, spacing: 12) {
                WidgetGalleryTile(family: .systemSmall, entry: entry, appearance: appearance, locked: locked)
                // Lock Screen widgets sit on the wallpaper, which is dark behind white text whatever the appearance.
                VStack(alignment: .leading, spacing: 12) {
                    WidgetGalleryTile(family: .accessoryRectangular, entry: entry, appearance: appearance, locked: locked)
                    WidgetGalleryTile(family: .accessoryCircular, entry: entry, appearance: appearance, locked: locked)
                }
                .padding(8)
                .frame(width: 182, height: 176, alignment: .topLeading)
                .background(wallpaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            WidgetGalleryTile(family: .accessoryInline, entry: entry, appearance: appearance, locked: locked)
                .padding(8)
                .frame(width: 364, alignment: .leading)
                .background(wallpaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            WidgetGalleryTile(family: .systemMedium, entry: entry, appearance: appearance, locked: locked)
            WidgetGalleryTile(family: .systemLarge, entry: entry, appearance: appearance, locked: locked)
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 16)
        .frame(width: 402, alignment: .leading)
        .background(backdrop)
        .environment(\.colorScheme, appearance.scheme)
    }

    private var wallpaper: LinearGradient {
        LinearGradient(colors: [Color(red: 0.2, green: 0.13, blue: 0.3), Color(red: 0.07, green: 0.06, blue: 0.1)], startPoint: .top, endPoint: .bottom)
    }

    /// Home Screen paper for light and dark; a dark wallpaper behind the accented and the Lock Screen widgets.
    @ViewBuilder
    private var backdrop: some View {
        switch appearance {
        case .light: Color(red: 0.89, green: 0.87, blue: 0.84)
        case .dark: Color(red: 0.06, green: 0.05, blue: 0.05)
        case .accented: LinearGradient(colors: [Color(red: 0.2, green: 0.12, blue: 0.3), Color(red: 0.08, green: 0.06, blue: 0.12)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - The gallery

public struct WidgetGalleryView: View {
    let request: WidgetGalleryRequest
    @State private var exported: String?

    public init(request: WidgetGalleryRequest) {
        self.request = request
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let exported {
                    Text(exported).font(.footnote).padding(8)
                }
                ForEach(request.scenes) { scene in
                    ForEach(request.appearances) { appearance in
                        WidgetGalleryPanel(scene: scene, appearance: appearance)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("widgetGallery")
        .task {
            guard request.exports else { return }
            exported = WidgetGalleryExport.write()
        }
    }
}

/// Writes every scene in every appearance as a 3x PNG: `the temporary folder's WidgetGallery/<scene>-<appearance>.png`.
@MainActor
enum WidgetGalleryExport {
    static func write() -> String {
        let folder = URL.temporaryDirectory.appending(path: "WidgetGallery", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written = 0
        for scene in WidgetGalleryScene.allCases {
            for appearance in WidgetGalleryAppearance.allCases {
                let renderer = ImageRenderer(content: WidgetGalleryPanel(scene: scene, appearance: appearance))
                renderer.scale = 3
                guard let data = renderer.uiImage?.pngData() else { continue }
                let url = folder.appending(path: "\(scene.rawValue)-\(appearance.rawValue).png", directoryHint: .notDirectory)
                if (try? data.write(to: url)) != nil { written += 1 }
            }
        }
        return "Wrote \(written) panels to \(folder.path)"
    }
}
#endif
