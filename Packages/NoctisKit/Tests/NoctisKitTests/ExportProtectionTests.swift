import Foundation
import Testing

@testable import NoctisCore

// Stage 1A, audit SEC-03: "Export my data" wrote the file atomically but with the default protection class, while the Journal and Coach files that the
// export copies are complete-while-locked. The export holds the same text, so it gets the same class, still written whole-or-not-at-all, and every
// cleanup removes it and any partial file a cut-short write could leave.
@MainActor
struct ExportProtectionTests {
    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "noctis-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: Protection

    @Test func theExportFileHasCompleteProtectionWhereThePlatformReportsOne() async throws {
        let bench = try DataBench()
        bench.wire()
        let url = try await bench.manager.exportFile()
        defer { bench.manager.discardExport() }
        // The simulator reports no class for a file; a device does. Where one is reported it must be the strong one.
        if let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
    }

    @Test func theCodeAsksForCompleteProtectionAndKeepsTheWholeOrNothingWrite() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/DataExport.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(text)
        #expect(code.contains("options: [.completeFileProtection]"), "the simulator reports no class, so the request itself is held to the code")
        #expect(!code.contains("UntilFirstUserAuthentication"), "not the weaker class")
        #expect(code.contains("replaceItemAt") && code.contains("moveItem(at: partial"), "the final file appears by rename: whole or absent")
        let manager = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisCore/DataManager.swift"), encoding: .utf8)
        #expect(RawDefaultsTests.code(manager).contains("DataExport.write(data, in:"), "the manager has no write of its own to forget the class")
    }

    // MARK: Whole or absent, and cleanup

    @Test func aSecondExportReplacesTheFirstAndLeavesOnlyTheFinalFile() async throws {
        let bench = try DataBench()
        bench.wire()
        let temporary = bench.roots.url(.temporary)
        _ = try await bench.manager.exportFile()
        let url = try await bench.manager.exportFile()
        defer { bench.manager.discardExport() }
        #expect(names(in: temporary) == [DataExport.fileName], "no partial file and no stray copy")
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) is [String: Any])
    }

    @Test func aWriteThatFailsThrowsAndLeavesNothingBehind() throws {
        let directory = try folder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(throws: (any Error).self) { try DataExport.write(Data("{}".utf8), in: directory) }
        #expect(names(in: directory).isEmpty, "a failed export leaves no partial file")
    }

    @Test func aWriteThatWorksLeavesTheFileAndNoPartialOne() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try DataExport.write(Data("{\"a\":1}".utf8), in: directory)
        #expect(names(in: directory) == [DataExport.fileName])
        #expect(try Data(contentsOf: url) == Data("{\"a\":1}".utf8))
    }

    @Test func aPartialFileLeftByACutShortWriteIsRemovedByDiscardAndWhenTheAppStarts() throws {
        let bench = try DataBench()
        let temporary = bench.roots.url(.temporary)
        let partial = temporary.appending(path: DataExport.partialFileName, directoryHint: .notDirectory)
        try Data("{".utf8).write(to: partial)
        bench.wire()
        #expect(!FileManager.default.fileExists(atPath: partial.path), "the manager clears it when it is made, as it does a finished export")

        try Data("{".utf8).write(to: partial)
        try Data("{}".utf8).write(to: temporary.appending(path: DataExport.fileName, directoryHint: .notDirectory))
        bench.manager.discardExport()
        #expect(names(in: temporary).isEmpty, "Share is done: both names are gone")
    }

    @Test func deletingEverythingAlsoRemovesAPartialExport() throws {
        let text = try String(
            contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/DataWiring.swift"), encoding: .utf8)
        #expect(RawDefaultsTests.code(text).contains("DataExport.remove(in: i.roots.url(.temporary))"))
    }

    @Test func theExportCreatesNoCopyOfTheJournalOutsideTheOneFile() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let before = names(in: bench.root)
        _ = try await bench.manager.exportFile()
        #expect(names(in: bench.roots.url(.temporary)) == [DataExport.fileName])
        bench.manager.discardExport()
        #expect(names(in: bench.roots.url(.temporary)).isEmpty)
        #expect(names(in: bench.root) == before, "nothing else was written anywhere beside the temporary folder")
    }
}
