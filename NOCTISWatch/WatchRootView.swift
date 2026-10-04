import NoctisWidgetKit
import SwiftUI

/// The first screen of the Watch app, until the pages exist (the next commit): what the Watch holds and how old it is.
struct WatchRootView: View {
    let model: WatchModel

    var body: some View {
        let state = model.state()
        VStack(spacing: 6) {
            Text("NOCTIS").font(.headline)
            Text(model.snapshot == nil ? "Open NOCTIS on your iPhone to get started" : "\(String(describing: state))")
                .font(.footnote)
                .multilineTextAlignment(.center)
            if let receivedAt = model.receivedAt {
                Text("Updated \(receivedAt, style: .relative) ago").font(.footnote)
            }
        }
        .padding()
    }
}
