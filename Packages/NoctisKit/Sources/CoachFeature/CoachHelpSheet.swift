import CoachKit
import DesignSystem
import SwiftUI

/// "Find help" (QA part 6): the numbers for the person's region, built in, so it works with no network; findahelpline.com is the way to more.
/// Region-aware: the device's region first, and a menu to pick another. It reads nothing about the person.
struct CoachHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var code: String

    init(locale: Locale = .autoupdatingCurrent) {
        _code = State(initialValue: CoachHelplines.region(for: locale).code)
    }

    private var region: CoachHelpRegion { CoachHelplines.region(for: code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    Text("If you might act on thoughts of harming yourself, call your local emergency number now. These lines are free to talk to, and open at any hour in most places.")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Menu {
                        ForEach(CoachHelplines.regions + [CoachHelplines.generic]) { item in
                            Button(item.name) { code = item.code }
                        }
                    } label: {
                        HStack {
                            Text(region.name).noctisFont(15, .semibold, relativeTo: .subheadline)
                            Image(systemName: "chevron.up.chevron.down").noctisIcon(12, .semibold, relativeTo: .subheadline)
                        }
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .padding(.horizontal, NoctisSpacing.md)
                        .frame(minHeight: 44)
                        .background(NoctisSection.coach.fill, in: Capsule())
                    }
                    .accessibilityLabel("Country: \(region.name)")
                    .accessibilityIdentifier("coach.help.region")

                    NoctisAppCard {
                        VStack(alignment: .leading, spacing: 0) {
                            row(region.emergency, emphasized: true)
                            ForEach(region.lines) { item in
                                Rectangle().fill(NoctisAppColor.hairline).frame(height: 1)
                                row(item, emphasized: false)
                            }
                        }
                    }

                    Text("Numbers can change. Check with your local services if a line doesn't connect.")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)

                    CoachPillButton(title: "More helplines worldwide", identifier: "coach.help.directory", symbol: "arrow.up.forward") {
                        if let url = CoachHelplines.directoryURL { openURL(url) }
                    }
                    .accessibilityHint("Opens findahelpline.com in your browser. Needs a connection.")
                }
                .padding(NoctisSpacing.xl)
            }
            .background(NoctisAppColor.bg.ignoresSafeArea())
            .navigationTitle("Find help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("coach.help.sheet")
    }

    private func row(_ line: CoachHelpline, emphasized: Bool) -> some View {
        Button {
            if let url = line.dialURL { openURL(url) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                Text(line.name)
                    .noctisFont(15, emphasized ? .semibold : .regular, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NoctisSpacing.xs)
                Text(line.number)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .monospacedDigit()
                    .foregroundStyle(NoctisAppColor.ink)
                Image(systemName: "phone.fill").noctisIcon(13, .semibold, relativeTo: .subheadline).foregroundStyle(NoctisAppColor.ink)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call \(line.name), \(line.number)")
    }
}
