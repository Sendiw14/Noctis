import NoctisWatchKit
import NoctisWidgetKit
import SwiftUI

/// The pages, one under another (the Digital Crown turns between them, and scrolls inside one that is taller than the screen), on black. The clock is
/// read every minute, so a day that has turned or a bedtime that has passed is never shown as it was.
struct WatchRootView: View {
    let model: WatchModel
    @State private var askResult: String?
    @State private var page: WatchPage
    @State private var showsBreathing = false

    init(model: WatchModel) {
        self.model = model
        _page = State(initialValue: model.initialPage)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let input = model.input(now: context.date)
            TabView(selection: $page) {
                RecoveryPageView(content: WatchPages.recovery(input)).tag(WatchPage.recovery)
                SleepPageView(content: WatchPages.sleep(input)).tag(WatchPage.sleep)
                HeartPageView(content: WatchPages.heart(input)).tag(WatchPage.heart)
                TonightPageView(content: WatchPages.tonight(input), systemDate: model.systemDate(for:), breathe: { showsBreathing = true }).tag(
                    WatchPage.tonight)
                SettingsPageView(
                    content: WatchPages.settings(input, version: model.versionText), isPhoneReachable: model.isPhoneReachable, askResult: askResult,
                    ask: { Task { askResult = await model.askPhone() } },
                    hapticsOn: Bindable(model.breath).hapticsOn
                )
                .tag(WatchPage.settings)
            }
            .tabViewStyle(.verticalPage)
        }
        .background(Color.black)
        .containerBackground(Color.black.gradient, for: .tabView)
        // A tap on a complication: the page it is about, through the one strict parser (anything else is ignored).
        .sheet(isPresented: $showsBreathing) { BreathFlowView(model: model.breath) }
        #if DEBUG
        .task {
            guard let script = model.debugBreathing else { return }
            page = .tonight
            model.breath.debugApply(script)
            showsBreathing = true
        }
        #endif
        .onOpenURL { url in
            if let link = WatchLink(url: url) { page = link.page }
        }
        #if DEBUG
        .redacted(reason: model.debugRedacted ? .privacy : [])
        #endif
    }
}
