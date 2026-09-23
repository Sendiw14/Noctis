import DesignSystem
import HealthProviding
import NoctisCore
import SwiftUI

public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        NoctisText(model.profile.name.isEmpty ? "Your Sleep Profile" : model.profile.name, style: .headline)
                        NoctisText(model.profile.primaryGoal.displayName, style: .caption, color: NoctisColor.textSecondary)
                    }
                    .padding(.vertical, NoctisSpacing.xs)
                }

                Section("Sleep Profile") {
                    Stepper(value: sleepGoalBinding, in: 6...9.5, step: 0.25) {
                        LabeledContent("Sleep Goal", value: formattedHours(model.profile.sleepGoalHours))
                    }
                    LabeledContent("Typical Wake Time", value: model.profile.typicalWakeTimeDescription)
                }

                Section("Health") {
                    LabeledContent("Data Source", value: model.healthSourceName)
                    LabeledContent("Authorization") {
                        NoctisConfidenceBadge(
                            label: authorizationLabel,
                            tint: model.healthAuthorization == .authorized ? NoctisColor.sage : NoctisColor.textTertiary
                        )
                    }
                    Button("Manage in Health App") {
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Subscription") {
                    NavigationLink {
                        PremiumPreviewView()
                    } label: {
                        HStack {
                            NoctisText("NOCTIS Premium", style: .body, color: NoctisColor.textPrimary)
                            Spacer()
                            NoctisPremiumBadge()
                        }
                    }
                }

                Section {
                    NavigationLink("Privacy") { PrivacyCenterView() }
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var authorizationLabel: String {
        switch model.healthAuthorization {
        case .authorized: "Connected"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        case .notDetermined: "Not Connected"
        }
    }

    private var sleepGoalBinding: Binding<Double> {
        Binding(
            get: { model.profile.sleepGoalHours },
            set: { newValue in model.updateProfile { $0.sleepGoalHours = newValue } }
        )
    }

    private func formattedHours(_ value: Double) -> String {
        let h = Int(value)
        let m = Int((value - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

#if canImport(UIKit)
import UIKit
#endif

struct PremiumPreviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                NoctisText("Sleep deeper. Understand yourself.", style: .title)
                ForEach(premiumFeatures, id: \.self) { feature in
                    HStack(spacing: NoctisSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NoctisColor.sage)
                        NoctisText(feature, style: .body)
                    }
                }
                NoctisText("Premium subscriptions arrive in a later build of NOCTIS.", style: .caption, color: NoctisColor.textTertiary)
                    .padding(.top, NoctisSpacing.md)
            }
            .padding(NoctisSpacing.xl)
        }
        .background(NoctisColor.canvas)
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }

    private let premiumFeatures = [
        "Advanced sleep stages & recovery depth",
        "Personal baselines & long-term trends",
        "AI Sleep Coach",
        "Personalized bedtime & Wind Down",
        "Weekly, monthly & yearly reviews",
    ]
}

struct PrivacyCenterView: View {
    var body: some View {
        List {
            Section("What NOCTIS Reads") {
                Text("Sleep analysis, heart rate, and heart rate variability — only the kinds you've granted in Health.")
            }
            Section("What Stays On Device") {
                Text("Your raw health samples are never copied off your device. NOCTIS reads them fresh from Health each time.")
            }
            Section("What Syncs") {
                Text("Nothing yet. Your profile and preferences are stored only on this device. iCloud sync is planned for a future build.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: NoctisSpacing.sm) {
            NoctisText("NOCTIS", style: .title)
            NoctisText("Better nights. A brighter you.", style: .caption, color: NoctisColor.textSecondary)
            NoctisText("Version 0.1.0", style: .caption, color: NoctisColor.textTertiary)
                .padding(.top, NoctisSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NoctisColor.canvas)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
