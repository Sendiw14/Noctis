#if DEBUG
import Darwin
import DesignSystem
import Foundation
import SwiftUI

/// DEBUG only: how many times each of Home's views has evaluated its
/// `body`, and the app's memory footprint, for the performance UI tests
/// (`-noctisDebugProbe`). The tests use them to check that a minute
/// passing re-evaluates the countdown text and not Home's root, and that
/// tab switches and Recovery zooms don't grow memory. Simulator numbers
/// are smoke tests, not the device budgets.
public enum HomeBodyProbe {
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    private static let lock = NSLock()

    @discardableResult
    static func hit(_ name: String) -> Bool {
        lock.withLock { counts[name, default: 0] += 1 }
        return true
    }

    static var summary: String {
        lock.withLock { counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
    }

    private static var vmInfo: task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// The app's physical memory footprint, in megabytes.
    public static var footprintMegabytes: Double {
        vmInfo.map { Double($0.phys_footprint) / 1_048_576 } ?? 0
    }

    /// Memory the allocator has handed back to the system but not unmapped ("reusable"): it is not in the footprint until the allocator uses it
    /// again, so the footprint alone swings by this much with no leak (QA_LEDGER.md: a 10 MB step in a run of twenty laps that was this). A leak is
    /// what the footprint plus this grows by.
    public static var reusableMegabytes: Double {
        vmInfo.map { Double($0.reusable) / 1_048_576 } ?? 0
    }
}

/// An invisible element that reports the probe, refreshed twice a second
/// on its own timeline, so reading it re-evaluates nothing else.
struct HomeDebugProbeView: View {
    let lowPower: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Color.clear
                .frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityIdentifier("debug.probe")
                .accessibilityLabel(HomeBodyProbe.summary + ";lowPower=\(lowPower ? 1 : 0)" + String(format: ";reusable=%.1f", HomeBodyProbe.reusableMegabytes))
                .accessibilityValue(String(format: "%.1f", HomeBodyProbe.footprintMegabytes))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Adds the probe overlay when the app was launched with
    /// `-noctisDebugProbe`.
    @ViewBuilder
    func homeDebugProbe(lowPower: Bool) -> some View {
        if ProcessInfo.processInfo.arguments.contains("-noctisDebugProbe") {
            overlay(alignment: .bottomTrailing) { HomeDebugProbeView(lowPower: lowPower) }
        } else {
            self
        }
    }
}
#endif
