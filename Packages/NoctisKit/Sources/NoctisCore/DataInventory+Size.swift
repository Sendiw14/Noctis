import Foundation

/// Where to look for the files and keys the inventory describes. The app's real places by default; a test hands it a
/// folder and a throwaway suite.
public nonisolated struct DataRoots: @unchecked Sendable {
    public var directories: [DataDirectory: URL]
    public var defaults: UserDefaults

    public init(directories: [DataDirectory: URL]? = nil, defaults: UserDefaults = NoctisUserDefaults.standard) {
        self.directories = directories ?? Dictionary(uniqueKeysWithValues: DataDirectory.allCases.map { ($0, $0.url) })
        self.defaults = defaults
    }

    public func url(_ directory: DataDirectory) -> URL {
        directories[directory] ?? directory.url
    }
}

/// How much room a category takes.
public nonisolated enum DataSize: Sendable, Equatable {
    /// This many bytes, all its own.
    case bytes(Int)
    /// Kept in a store it shares with other categories; the store's whole size.
    case shared(Int, with: [DataCategoryID])
    /// Not on this iPhone's disk: Apple holds it, or it is only in memory.
    case notStored
}

nonisolated extension DataInventory {
    // MARK: Files

    /// The bytes of the file at `url`, or of everything under it when it is a folder; 0 when it is not there.
    static func bytes(at url: URL) -> Int {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return ((try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0 }
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
        }
        return total
    }

    /// The bytes one location holds; nil where there is nothing of NOCTIS's on disk to measure.
    func bytes(of location: DataLocation, roots: DataRoots) -> Int? {
        switch location {
        case .file(let directory, let path):
            return Self.bytes(at: roots.url(directory).appending(path: path, directoryHint: .notDirectory))
        case .folder(let directory, let path):
            return Self.bytes(at: roots.url(directory).appending(path: path, directoryHint: .isDirectory))
        case .database(let directory, let path):
            let store = roots.url(directory).appending(path: path, directoryHint: .notDirectory)
            let folder = store.deletingLastPathComponent()
            let name = store.lastPathComponent
            let base = (name as NSString).deletingPathExtension
            var total = 0
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                if entry == name || entry.hasPrefix(name + "-") || entry == "." + base + "_SUPPORT" {
                    total += Self.bytes(at: folder.appending(path: entry))
                }
            }
            return total
        case .defaults(let keys):
            var total = 0
            for key in keys {
                guard let value = roots.defaults.object(forKey: key),
                      let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { continue }
                total += data.count
            }
            return total
        case .keychain:
            return SystemAccountKeychain().byteCount
        case .system, .memory:
            return nil
        }
    }

    /// How much room `category` takes on this iPhone.
    public func size(of category: DataCategory, roots: DataRoots = DataRoots()) -> DataSize {
        var own = 0
        var measured = false
        for location in category.locations {
            guard let bytes = bytes(of: location, roots: roots) else { continue }
            measured = true
            if case .database = location, let others = sharing(location, with: category), !others.isEmpty {
                return .shared(bytes, with: others)
            }
            own += bytes
        }
        return measured ? .bytes(own) : .notStored
    }

    /// The other categories that keep their data in the same database as `category`.
    private func sharing(_ location: DataLocation, with category: DataCategory) -> [DataCategoryID]? {
        categories.filter { $0.id != category.id && $0.locations.contains(location) }.map(\.id)
    }

    /// Everything NOCTIS keeps on this iPhone, each place counted once.
    public func totalBytes(roots: DataRoots = DataRoots()) -> Int {
        var counted: [DataLocation] = []
        var total = 0
        for category in categories {
            for location in category.locations where !counted.contains(location) {
                counted.append(location)
                total += bytes(of: location, roots: roots) ?? 0
            }
        }
        return total
    }

    /// "12 KB", "1.4 MB", "Less than 1 KB".
    public static func describe(bytes: Int) -> String {
        if bytes <= 0 { return "Nothing stored" }
        if bytes < 1024 { return "Less than 1 KB" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
