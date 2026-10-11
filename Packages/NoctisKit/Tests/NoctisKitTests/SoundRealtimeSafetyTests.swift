import Darwin
import Foundation
import Synchronization
import Testing

@testable import SoundKit

/// The audio thread must not allocate (APP_RULES.md R31). This hooks `malloc_logger`, the hook the
/// system's own allocation tools use, and counts what the rendering thread allocates while it
/// renders every sound, a crossfade, a fade and a change of gain. A deliberate allocation first
/// proves the hook counts at all.
///
/// iOS 27 marks the strictly real-time render block unavailable to Swift ("Swift is not supported
/// for use with audio realtime threads"); this is how the Swift one is held to the same rule.
struct SoundRealtimeSafetyTests {
    typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    /// Thread and Address Sanitizer replace the allocator, so `malloc_logger` sees nothing under them: both tests below would prove nothing
    /// there (the counting test fails, the zero test passes for the wrong reason). They run in every other configuration (QA_LEDGER.md).
    nonisolated static let allocatorIsReplaced: Bool = {
        let everything = UnsafeMutableRawPointer(bitPattern: -2)
        let names: [String] = ["__tsan_init", "__asan_init", "__asan_version_mismatch_check_v8"]
        return names.contains { name in dlsym(everything, name) != nil }
    }()

    static let watched = Atomic<UInt>(0)
    static let count = Atomic<Int>(0)

    static let hook: MallocLogger = { _, _, _, _, _, _ in
        if UInt(bitPattern: pthread_self()) == SoundRealtimeSafetyTests.watched.load(ordering: .relaxed) {
            SoundRealtimeSafetyTests.count.wrappingAdd(1, ordering: .relaxed)
        }
    }

    /// Runs `body` on this thread with the hook counting this thread's allocations; returns the count.
    static func allocations(during body: () -> Void) -> Int? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
        let slot = symbol.assumingMemoryBound(to: MallocLogger?.self)
        let previous = slot.pointee
        count.store(0, ordering: .relaxed)
        watched.store(UInt(bitPattern: pthread_self()), ordering: .relaxed)
        slot.pointee = hook
        body()
        slot.pointee = previous
        watched.store(0, ordering: .relaxed)
        return count.load(ordering: .relaxed)
    }

    @Test(.disabled(if: SoundRealtimeSafetyTests.allocatorIsReplaced, "a sanitizer replaces the allocator, so the hook sees nothing"))
    func theHookCountsADeliberateAllocation() throws {
        let counted = try #require(Self.allocations {
            let box = UnsafeMutablePointer<Int>.allocate(capacity: 64)
            box.initialize(repeating: 1, count: 64)
            box.deallocate()
        })
        #expect(counted >= 1, "the malloc hook saw nothing, so it proves nothing")
    }

    @Test(.disabled(if: SoundRealtimeSafetyTests.allocatorIsReplaced, "a sanitizer replaces the allocator, so the hook sees nothing"))
    func renderingAllocatesNothing() throws {
        let renderer = SoundRenderer()
        let frames = 1156
        let l = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { l.deallocate(); r.deallocate() }
        // `allCases` builds an array on every access; the test makes it once, off the counted path.
        let kinds = SoundKind.allCases
        // Once through everything first, so anything that is allowed to happen once has happened.
        for kind in kinds {
            renderer.apply(SoundCommand(kind: kind, gain: 0.4))
            renderer.renderStereo(left: l, right: r, count: frames)
        }

        for kind in kinds {
            let counted = try #require(Self.allocations {
                // `while`, not `for ... in 0..<n`: a range loop allocates in a Debug build, and this
                // closure is what is being counted.
                renderer.apply(SoundCommand(kind: kind, gain: 0.5, crossfadeSeconds: 0.2))
                var n = 0
                while n < 40 { renderer.renderStereo(left: l, right: r, count: frames); n += 1 }
                renderer.apply(SoundCommand(kind: kind, gain: 0.9, fader: nil))
                n = 0
                while n < 5 { renderer.renderStereo(left: l, right: r, count: 333); n += 1 }
                renderer.apply(SoundCommand(kind: kind, gain: 0.9, fader: 0, faderSeconds: 0.1))
                n = 0
                while n < 10 { renderer.renderStereo(left: l, right: r, count: frames); n += 1 }
                renderer.apply(SoundCommand(kind: kind, gain: 0.9, fader: 1, faderSeconds: 0.1))
                n = 0
                while n < 10 { renderer.renderStereo(left: l, right: r, count: 1); n += 1 }
            })
            #expect(counted == 0, Comment(rawValue: "rendering \(kind) allocated \(counted) times"))
        }
    }

    // MARK: A second guard: what the render path may not even mention

    /// The audio thread's source files, minus comments and strings, name none of the things that
    /// allocate, wait or hand work to the runtime.
    @Test func theRenderPathNamesNothingItMayNotUse() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SoundKit")
        let forbidden = [
            "Task", "await", "async", "DispatchQueue", "NSLock", "Mutex", "OSAllocatedUnfairLock", "NotificationCenter",
            "Array(", "[Float](", ".append(", "String(", "Data(", "print(", "Logger", "@MainActor", "actor ", "Date()", "UserDefaults",
            // A range loop is generic iteration: in a Debug build it allocates on every pass (found by the test above).
            " in 0..<", ".map {", ".reduce(", ".forEach", ".filter {",
        ]
        for name in ["SoundRenderer.swift", "SoundSources.swift", "SoundVoices.swift", "SoundDSP.swift"] {
            let url = directory.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("could not read \(url.path)")
                continue
            }
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { return "" }
                    if let range = line.range(of: "//") { return String(line[..<range.lowerBound]) }
                    return String(line)
                }
            // The offline synth (below the bank, in SoundVoices.swift) allocates by design: it never runs on the audio thread.
            let stop = code.firstIndex { $0.contains("public enum SoundSynth") } ?? code.count
            for (number, line) in code.enumerated() where number < stop {
                for word in forbidden where line.contains(word) {
                    // The words appear inside doc comments and the mixer's own description, which are filtered above.
                    Issue.record("\(name):\(number + 1) mentions \(word): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }
}
