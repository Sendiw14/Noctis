import Foundation
import Testing

@testable import NightFeature
@testable import NightKit

// The meditation's engine (APP_RULES.md R34): the schedule of every category at every length, the
// chimes (made in code), and the words in the String Catalog.

nonisolated struct MeditationScheduleTests {
    struct Case: Sendable {
        let category: MeditationCategory
        let minutes: Int
    }

    static let cases: [Case] = MeditationCategory.allCases.flatMap { category in
        MeditationSchedule.durations.map { Case(category: category, minutes: $0) }
    }

    @Test func theLengthsAreFiveTenAndTwentyMinutes() {
        #expect(MeditationSchedule.durations == [5, 10, 20])
        #expect(MeditationSchedule.durations.contains(MeditationSchedule.defaultMinutes))
        #expect(MeditationCategory.allCases.map(\.rawValue) == ["sleep", "relax", "breathing", "bodyScan", "quietMind"])
    }

    @Test(arguments: cases)
    func theTotalIsExactlyTheChosenLengthWithAChimeAtBothEnds(item: Case) {
        let schedule = MeditationSchedule(category: item.category, minutes: item.minutes)
        #expect(schedule.totalSeconds == Double(item.minutes * 60))
        #expect(schedule.cues.first == MeditationCue(at: 0, lineKey: nil, chime: .start))
        #expect(schedule.cues.last == MeditationCue(at: schedule.totalSeconds, lineKey: nil, chime: .end))
        #expect(schedule.cues.filter { $0.chime == .start }.count == 1)
        #expect(schedule.cues.filter { $0.chime == .end }.count == 1)
    }

    @Test(arguments: cases)
    func theCuesComeInTimeOrderInsideTheSession(item: Case) {
        let schedule = MeditationSchedule(category: item.category, minutes: item.minutes)
        let times = schedule.cues.map(\.at)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        #expect(times.allSatisfy { $0 >= 0 && $0 <= schedule.totalSeconds })
    }

    @Test(arguments: cases)
    func linesAreEvenlySpacedWithALeadInAndAQuietTail(item: Case) {
        let schedule = MeditationSchedule(category: item.category, minutes: item.minutes)
        let lines = schedule.lineCues
        #expect(lines.count == item.category.lineCount(minutes: item.minutes))
        guard item.category.hasLines else {
            #expect(lines.isEmpty && schedule.lineGap == 0)
            return
        }
        #expect(lines.first?.at == MeditationSchedule.leadIn)
        let gap = (schedule.totalSeconds - MeditationSchedule.leadIn - MeditationSchedule.tail) / Double(lines.count)
        #expect(abs(schedule.lineGap - gap) < 1e-9)
        for (a, b) in zip(lines, lines.dropFirst()) {
            #expect(abs((b.at - a.at) - gap) < 1e-9, Comment(rawValue: "\(item.category) \(item.minutes) min: uneven"))
        }
        // The last line has its whole turn, then the tail, then the closing chime.
        let last = lines.last?.at ?? 0
        #expect(abs((last + gap) - (schedule.totalSeconds - MeditationSchedule.tail)) < 1e-9)
        #expect(gap >= 20, "a line stays long enough to be read and rested in")
    }

    @Test(arguments: cases)
    func twoSoftChimesMarkTheStartOfTheSecondAndThirdPart(item: Case) {
        let schedule = MeditationSchedule(category: item.category, minutes: item.minutes)
        let transitions = schedule.cues.filter { $0.chime == .transition }
        #expect(transitions.count == 2)
        if item.category.hasLines {
            let count = schedule.lineCues.count
            let expected = [schedule.lineCues[count / 3].at, schedule.lineCues[2 * count / 3].at]
            #expect(transitions.map(\.at) == expected, "each sounds as a line begins")
            #expect(transitions.allSatisfy { $0.lineKey != nil })
        } else {
            #expect(transitions.map(\.at) == [schedule.totalSeconds / 3, 2 * schedule.totalSeconds / 3])
        }
    }

    @Test(arguments: MeditationSchedule.durations)
    func theBodyScanWalksTwelvePlacesFromHeadToToeInEvenSteps(minutes: Int) {
        let schedule = MeditationSchedule(category: .bodyScan, minutes: minutes)
        #expect(schedule.lineCues.map(\.lineKey) == MeditationCategory.bodyScan.poolKeys.map(Optional.some))
        #expect(MeditationCategory.bodyScan.poolKeys.first == "meditation.bodyScan.01")
        #expect(MeditationCategory.bodyScan.poolKeys.last == "meditation.bodyScan.12")
        let gap = (Double(minutes * 60) - 30) / 12
        #expect(abs(schedule.lineGap - gap) < 1e-9)
    }

    @Test func theBodyScanStepsAre22Point5And47Point5And97Point5Seconds() {
        #expect(MeditationSchedule(category: .bodyScan, minutes: 5).lineGap == 22.5)
        #expect(MeditationSchedule(category: .bodyScan, minutes: 10).lineGap == 47.5)
        #expect(MeditationSchedule(category: .bodyScan, minutes: 20).lineGap == 97.5)
    }

    @Test(arguments: [MeditationCategory.sleep, .relax, .breathing])
    func aLongerSessionSaysMoreAndKeepsTheArcFromFirstLineToLast(category: MeditationCategory) {
        let counts = MeditationSchedule.durations.map { category.lineCount(minutes: $0) }
        #expect(counts == [6, 9, 12])
        for minutes in MeditationSchedule.durations {
            let keys = MeditationSchedule(category: category, minutes: minutes).lineCues.compactMap(\.lineKey)
            let pool = category.poolKeys
            #expect(keys.first == pool.first && keys.last == pool.last)
            #expect(Set(keys).count == keys.count, "no line is said twice")
            let positions = keys.compactMap { pool.firstIndex(of: $0) }
            #expect(positions == positions.sorted(), "the order of the pool is kept")
        }
    }

    @Test func quietMindSaysNothingAtAll() {
        #expect(!MeditationCategory.quietMind.hasLines)
        #expect(MeditationCategory.quietMind.poolKeys.isEmpty)
        for minutes in MeditationSchedule.durations {
            let schedule = MeditationSchedule(category: .quietMind, minutes: minutes)
            #expect(schedule.lineCues.isEmpty)
            #expect(schedule.lineKey(at: 0) == nil && schedule.lineKey(at: Double(minutes * 30)) == nil)
            #expect(schedule.cues.map(\.chime) == [.start, .transition, .transition, .end])
        }
    }

    @Test func thePoolsAreTwelveNumberedKeysEach() {
        for category in MeditationCategory.allCases where category.hasLines {
            let keys = category.poolKeys
            #expect(keys.count == 12 && Set(keys).count == 12)
            #expect(keys.allSatisfy { $0.hasPrefix("meditation.\(category.rawValue).") })
        }
    }

    @Test func theLineOnScreenIsTheLatestBeganAndNoneBeforeTheFirst() {
        let schedule = MeditationSchedule(category: .bodyScan, minutes: 5)
        let keys = MeditationCategory.bodyScan.poolKeys
        #expect(schedule.lineKey(at: 0) == nil)
        #expect(schedule.lineKey(at: 5.999) == nil)
        #expect(schedule.lineKey(at: 6) == keys[0])
        #expect(schedule.lineKey(at: 28.499) == keys[0])
        #expect(schedule.lineKey(at: 28.5) == keys[1])
        #expect(schedule.lineKey(at: 299) == keys[11], "the last line stays through the quiet tail")
        #expect(schedule.lineKey(at: 300) == keys[11])
    }

    @Test func theNextCueIsTheFirstAfterNow() {
        let schedule = MeditationSchedule(category: .bodyScan, minutes: 5)
        #expect(schedule.nextCueTime(after: -1) == 0)
        #expect(schedule.nextCueTime(after: 0) == 6)
        #expect(schedule.nextCueTime(after: 6) == 28.5)
        #expect(schedule.nextCueTime(after: 299.9) == 300)
        #expect(schedule.nextCueTime(after: 300) == nil)
    }

    @Test func progressRunsFromZeroToOne() {
        #expect(meditationProgress(elapsed: 0, total: 600) == 0)
        #expect(meditationProgress(elapsed: 150, total: 600) == 0.25)
        #expect(meditationProgress(elapsed: 900, total: 600) == 1)
        #expect(meditationProgress(elapsed: -5, total: 600) == 0)
        #expect(meditationProgress(elapsed: 5, total: 0) == 0)
    }
}

nonisolated struct ChimeSynthTests {
    @Test(arguments: MeditationChimeKind.allCases)
    func aChimeIsAThisLongSineStartingAtSilence(kind: MeditationChimeKind) {
        let samples = ChimeSynth.render(kind)
        #expect(samples.count == Int(kind.seconds * ChimeSynth.sampleRate))
        #expect(samples[0] == 0, "it starts at zero, so there is no click")
        #expect(samples.last == 0, "and ends at zero")
        #expect(samples.allSatisfy { $0.isFinite })
    }

    @Test(arguments: MeditationChimeKind.allCases)
    func itIsSoftAndNeverClips(kind: MeditationChimeKind) {
        let samples = ChimeSynth.render(kind)
        let loudest = samples.map { abs($0) }.max() ?? 0
        #expect(loudest <= ChimeSynth.peak)
        #expect(loudest > ChimeSynth.peak * 0.9)
        #expect(loudest < 0.5)
    }

    @Test(arguments: MeditationChimeKind.allCases)
    func theFirstSecondHasTheRightPitch(kind: MeditationChimeKind) {
        let samples = ChimeSynth.render(kind)
        var crossings = 0
        var i = 1
        let oneSecond = Int(ChimeSynth.sampleRate)
        while i < oneSecond {
            if (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
            i += 1
        }
        // A sine crosses zero twice a cycle.
        let measured = Double(crossings) / 2
        #expect(abs(measured - kind.frequency) < 2, Comment(rawValue: "\(kind) is \(measured) Hz"))
    }

    @Test(arguments: MeditationChimeKind.allCases)
    func itDecaysSoftlyToNothing(kind: MeditationChimeKind) {
        let samples = ChimeSynth.render(kind)
        let window = Int(0.25 * ChimeSynth.sampleRate)
        var energies: [Double] = []
        var start = 0
        while start + window <= samples.count {
            var sum = 0.0
            var i = start
            while i < start + window {
                sum += Double(samples[i]) * Double(samples[i])
                i += 1
            }
            energies.append((sum / Double(window)).squareRoot())
            start += window
        }
        #expect(zip(energies, energies.dropFirst()).allSatisfy { $0 > $1 }, "each quarter second is quieter than the last")
        #expect((energies.last ?? 1) < Double(ChimeSynth.peak) * 0.01, "gone by the end: under -40 dB")
    }

    @Test func theThreeChimesSoundDifferentAndTheEndOneIsLowestAndLongest() {
        let kinds = MeditationChimeKind.allCases
        #expect(Set(kinds.map(\.frequency)).count == 3)
        #expect(MeditationChimeKind.end.frequency < MeditationChimeKind.start.frequency)
        #expect(MeditationChimeKind.end.seconds == kinds.map(\.seconds).max())
    }

    @Test func theWavIsAValidSixteenBitMonoFile() {
        let samples = ChimeSynth.render(frequency: 440, seconds: 0.5)
        let data = ChimeSynth.wav(samples)
        #expect(data.count == 44 + samples.count * 2)
        func text(_ range: Range<Int>) -> String { String(decoding: data[range], as: UTF8.self) }
        func u32(_ at: Int) -> UInt32 { data[at..<at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func u16(_ at: Int) -> UInt16 { UInt16(data[at]) | UInt16(data[at + 1]) << 8 }
        #expect(text(0..<4) == "RIFF" && text(8..<12) == "WAVE" && text(12..<16) == "fmt " && text(36..<40) == "data")
        #expect(u32(4) == UInt32(36 + samples.count * 2))
        #expect(u32(16) == 16 && u16(20) == 1 && u16(22) == 1)
        #expect(u32(24) == 44_100 && u32(28) == 88_200 && u16(32) == 2 && u16(34) == 16)
        #expect(u32(40) == UInt32(samples.count * 2))
    }

    @Test func aSampleBecomesItsSixteenBitValue() {
        let data = ChimeSynth.wav([0, 0.5, -0.5, 1, -1, 2])
        func s16(_ index: Int) -> Int16 { Int16(bitPattern: UInt16(data[44 + index * 2]) | UInt16(data[45 + index * 2]) << 8) }
        #expect(s16(0) == 0)
        #expect(s16(1) == 16384 || s16(1) == 16383)
        #expect(s16(2) == -16384 || s16(2) == -16383)
        #expect(s16(3) == Int16.max && s16(4) == -Int16.max)
        #expect(s16(5) == Int16.max, "clipped, never wrapped")
    }
}

nonisolated struct MeditationCatalogTests {
    static let bannedWords = [
        "anxiety", "anxious", "stress", "cure", "treat", "heal", "therap", "medical", "clinical", "diagnos", "insomnia", "depress",
        "fall asleep", "sleep better", "sleep soundly", "guarantee", "will help", "doctor", "disorder", "symptom", "medication", "proven", "science", "study",
    ]

    static var everyKey: [String] {
        MeditationCategory.allCases.flatMap { [$0.titleKey, $0.summaryKey] + $0.poolKeys }
    }

    @Test(arguments: everyKey)
    func everyKeyIsInTheCatalog(key: String) {
        let text = MeditationCopy.string(key)
        #expect(text != key, Comment(rawValue: "\(key) is missing from Meditation.xcstrings"))
        #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test func thereAreFiftyEightStringsAndNoneUnused() {
        #expect(Self.everyKey.count == 5 * 2 + 4 * 12)
        #expect(Set(Self.everyKey).count == Self.everyKey.count)
    }

    @Test func linesAreShortAndCalm() {
        for category in MeditationCategory.allCases {
            for key in category.poolKeys {
                let text = MeditationCopy.string(key)
                #expect(text.split(separator: " ").count <= 12, Comment(rawValue: "\(key) is long: \(text)"))
                #expect(text.hasSuffix(".") && !text.contains("!") && !text.contains("?"), Comment(rawValue: "\(key) is not calm: \(text)"))
            }
        }
    }

    @Test func nothingSaidIsAMedicalTherapeuticOrSleepClaim() {
        let words = (Self.everyKey.map { MeditationCopy.string($0) } + [MeditationCopy.line, MeditationCopy.spokenNote, MeditationCopy.finishedTitle])
            .joined(separator: " ").lowercased()
        for banned in Self.bannedWords {
            #expect(!words.contains(banned), Comment(rawValue: "the meditation copy says \"\(banned)\""))
        }
    }

    @Test func theCategoriesAreNamedAsAskedFor() {
        #expect(MeditationCategory.allCases.map { MeditationCopy.title($0) } == ["Sleep", "Relax", "Breathing", "Body scan", "Quiet mind"])
        #expect(MeditationCopy.finishedLine(category: .bodyScan, minutes: 10) == "Body scan, 10 min.")
    }

    @Test func theBodyScanLinesGoFromTheHeadToTheFeet() {
        let lines = MeditationCategory.bodyScan.poolKeys.map { MeditationCopy.string($0).lowercased() }
        #expect(lines.first?.contains("head") == true)
        #expect(lines.last?.contains("feet") == true)
        #expect(lines.firstIndex { $0.contains("shoulders") } ?? 99 < lines.firstIndex { $0.contains("hips") } ?? 0)
        #expect(lines.firstIndex { $0.contains("belly") } ?? 99 < lines.firstIndex { $0.contains("knees") } ?? 0)
    }
}
