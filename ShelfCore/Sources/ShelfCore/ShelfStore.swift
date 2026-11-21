import Foundation
import Observation

/// The shelf: a directory of files plus a small JSON manifest describing them.
///
/// Everything the shelf discards goes to the Trash rather than being deleted,
/// so a sweep that takes something you still wanted is recoverable.
@MainActor @Observable
public final class ShelfStore {
    /// Newest first.
    public private(set) var items: [ShelfItem] = []
    public let directory: URL

    /// The shelf's "day" starts at this hour, not midnight, so a screenshot
    /// taken at 11:58 PM isn't swept two minutes later.
    public nonisolated static let dayStartHour = 4

    @ObservationIgnored private let manifestURL: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let discard: (URL) throws -> Void
    @ObservationIgnored private let fileManager = FileManager.default

    public init(
        root: URL,
        now: @escaping () -> Date = Date.init,
        discard: ((URL) throws -> Void)? = nil
    ) {
        directory = root.appendingPathComponent("shelf", isDirectory: true)
        manifestURL = root.appendingPathComponent("shelf.json")
        self.now = now
        self.discard = discard ?? { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    public func url(for item: ShelfItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    public func item(_ id: UUID) -> ShelfItem? {
        items.first { $0.id == id }
    }

    public var newest: ShelfItem? { items.first }

    // MARK: Adding

    /// Takes a file onto the shelf. Captures are moved (that is the point: they
    /// stop piling up in the screenshots folder); dropped files are copied, so
    /// the original stays where it was.
    @discardableResult
    public func ingest(fileAt source: URL, as kind: ShelfItem.Source, move: Bool) throws -> ShelfItem {
        let name = uniqueName(for: source.lastPathComponent)
        let destination = directory.appendingPathComponent(name)
        if move {
            try fileManager.moveItem(at: source, to: destination)
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        return insert(ShelfItem(fileName: name, addedAt: now(), source: kind))
    }

    /// Parks raw data (an image dragged out of a browser, say) as a new file.
    @discardableResult
    public func ingest(data: Data, suggestedName: String) throws -> ShelfItem {
        let name = uniqueName(for: suggestedName)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return insert(ShelfItem(fileName: name, addedAt: now(), source: .dropped))
    }

    /// The shelf item a dropped file already is, or duplicates.
    ///
    /// Two cases: an item dragged out of the shelf and dropped straight back
    /// (a change of mind mid-drag), and a copy of one that went somewhere
    /// else first, say the Desktop, and came back. Either way the shelf
    /// shouldn't gain a second copy.
    public func existingItem(matching url: URL) -> ShelfItem? {
        // Drags hand over file *reference* URLs (/.file/id=…); turn those
        // back into real paths before comparing.
        let resolved = ((url as NSURL).filePathURL ?? url).resolvingSymlinksInPath().standardizedFileURL
        let shelfPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        if resolved.deletingLastPathComponent().path == shelfPath {
            return items.first { $0.fileName == resolved.lastPathComponent }
        }
        guard let size = fileSize(resolved) else { return nil }
        return items.first { item in
            let candidate = self.url(for: item)
            return fileSize(candidate) == size && fileManager.contentsEqual(atPath: candidate.path, andPath: resolved.path)
        }
    }

    /// The shelf item whose file holds exactly these bytes, if any.
    public func existingItem(matching data: Data) -> ShelfItem? {
        items.first { item in
            let candidate = url(for: item)
            return fileSize(candidate) == data.count && (try? Data(contentsOf: candidate)) == data
        }
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    private func insert(_ item: ShelfItem) -> ShelfItem {
        items.insert(item, at: 0)
        save()
        return item
    }

    // MARK: Changing

    public func setPinned(_ pinned: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned = pinned
        save()
    }

    /// Swaps an item's file for new contents (a pixelated copy) while keeping
    /// its place and identity on the shelf. The old file goes to the Trash.
    @discardableResult
    public func replaceContents(of id: UUID, with data: Data, fileExtension: String, suffix: String) throws -> ShelfItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let old = items[index]
        let base = (old.fileName as NSString).deletingPathExtension
        let name = uniqueName(for: "\(base) \(suffix).\(fileExtension)")
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        try? discard(url(for: old))
        items[index].fileName = name
        save()
        return items[index]
    }

    // MARK: Removing

    public func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for item in items where ids.contains(item.id) {
            try? discard(url(for: item))
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    /// Clears the shelf. Pinned items stay unless asked otherwise.
    public func clear(includingPinned: Bool = false) {
        remove(Set(items.filter { includingPinned || !$0.pinned }.map(\.id)))
    }

    /// The daily sweep: removes unpinned items added before the start of the
    /// current shelf day. Returns how many went.
    @discardableResult
    public func purgeExpired() -> Int {
        let cutoff = Self.dayStart(containing: now())
        let expired = items.filter { !$0.pinned && $0.addedAt < cutoff }
        remove(Set(expired.map(\.id)))
        return expired.count
    }

    /// The most recent `dayStartHour` boundary at or before `date`.
    public nonisolated static func dayStart(containing date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = dayStartHour
        guard let boundary = calendar.date(from: components) else { return date }
        if boundary <= date { return boundary }
        return calendar.date(byAdding: .day, value: -1, to: boundary) ?? boundary
    }

    // MARK: Disk

    private func uniqueName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var counter = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func load() {
        var loaded: [ShelfItem] = []
        if let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            loaded = (try? decoder.decode([ShelfItem].self, from: data)) ?? []
        }

        // Forget entries whose file has gone (deleted by hand, say).
        loaded = loaded.filter { fileManager.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }

        // Adopt files with no entry, so nothing in the folder escapes the sweep.
        let known = Set(loaded.map(\.fileName))
        let onDisk = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in onDisk where !name.hasPrefix(".") && !known.contains(name) {
            let attributes = try? fileManager.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            let created = attributes?[.creationDate] as? Date ?? now()
            loaded.append(ShelfItem(fileName: name, addedAt: created, source: .dropped))
        }

        items = loaded.sorted { $0.addedAt > $1.addedAt }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
