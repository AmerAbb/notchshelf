import Foundation
import os

let log = Logger(subsystem: "com.amerabb.notchshelf", category: "capture")

/// Calls back (on the main queue) with files that newly appear in one
/// directory. It snapshots the listing on start, so files already there are
/// never reported.
///
/// Listing runs on the watcher's own queue, never the main thread: reading a
/// privacy-protected folder like the Desktop blocks the reading thread until
/// you answer macOS's permission prompt, and that must not freeze the app.
public final class DirectoryWatcher {
    public let url: URL
    private let queue: DispatchQueue
    private let onNew: ([URL]) -> Void
    // Only touched on `queue`.
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []

    public init(url: URL, onNew: @escaping ([URL]) -> Void) {
        self.url = url
        self.onNew = onNew
        queue = DispatchQueue(label: "notchshelf.watch.\(url.lastPathComponent)")
        // Even opening a protected folder waits on the prompt, so all of it
        // happens on the watcher's queue.
        queue.async { [weak self] in self?.start() }
    }

    deinit {
        let queue = queue
        let source = source
        queue.async { source?.cancel() }
    }

    private func start() {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            log.error("can't watch \(self.url.path, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        known = list()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue
        )
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        log.info("watching \(self.url.path, privacy: .public)")
    }

    private func list() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
    }

    private func scan() {
        let current = list()
        let added = current.subtracting(known)
        known = current
        guard !added.isEmpty else { return }
        log.info("new in \(self.url.lastPathComponent, privacy: .public): \(added.sorted().joined(separator: ", "), privacy: .public)")
        let urls = added.sorted().map { url.appendingPathComponent($0) }
        DispatchQueue.main.async { [onNew] in onNew(urls) }
    }
}

/// Watches the folders where screenshots and Simulator captures land, and moves
/// each new capture onto the shelf.
@MainActor
public final class CaptureWatcher {
    public struct Location: Equatable {
        public var url: URL
        public var accepts: Set<ShelfItem.Source>

        public init(url: URL, accepts: Set<ShelfItem.Source>) {
            self.url = url.standardizedFileURL
            self.accepts = accepts
        }
    }

    public var onCapture: ((ShelfItem) -> Void)?
    public private(set) var locations: [Location] = []

    private let store: ShelfStore
    private var watchers: [DirectoryWatcher] = []
    private var inFlight: Set<String> = []

    public init(store: ShelfStore) {
        self.store = store
    }

    /// Points the watcher at a set of folders. Two locations in the same
    /// folder (screenshots and the Simulator both default to the Desktop) are
    /// merged. Calling this again with the same folders does nothing, so it is
    /// cheap to call whenever the system settings might have changed.
    public func configure(_ requested: [Location]) {
        var merged: [Location] = []
        for location in requested {
            if let index = merged.firstIndex(where: { $0.url == location.url }) {
                merged[index].accepts.formUnion(location.accepts)
            } else {
                merged.append(location)
            }
        }
        guard merged != locations || watchers.count != merged.count else { return }
        locations = merged
        watchers = merged.map { location in
            DirectoryWatcher(url: location.url) { [weak self] urls in
                MainActor.assumeIsolated {
                    self?.handle(urls, accepts: location.accepts)
                }
            }
        }
    }

    private func handle(_ urls: [URL], accepts: Set<ShelfItem.Source>) {
        for url in urls where !inFlight.contains(url.path) {
            // Cheap name check first, so unrelated Desktop churn costs nothing.
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            inFlight.insert(url.path)
            waitUntilSettled(url, accepts: accepts, lastSize: -1, attempt: 0)
        }
    }

    /// Recordings are still being written when they first appear, so wait for
    /// the size to stop changing before moving anything.
    private func waitUntilSettled(_ url: URL, accepts: Set<ShelfItem.Source>, lastSize: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
                guard let size else {
                    self.inFlight.remove(url.path)  // gone already
                    return
                }
                if size != lastSize || size == 0, attempt < 150 {
                    self.waitUntilSettled(url, accepts: accepts, lastSize: size, attempt: attempt + 1)
                    return
                }
                self.inFlight.remove(url.path)
                self.take(url, accepts: accepts)
            }
        }
    }

    private func take(_ url: URL, accepts: Set<ShelfItem.Source>) {
        let tagged = CaptureClassifier.isTaggedScreenCapture(url)
        guard let kind = CaptureClassifier.classify(fileName: url.lastPathComponent, isTaggedScreenCapture: tagged),
              accepts.contains(kind)
        else {
            log.debug("ignored \(url.lastPathComponent, privacy: .public) (tagged: \(tagged))")
            return
        }
        do {
            let item = try store.ingest(fileAt: url, as: kind, move: true)
            log.info("shelved \(item.fileName, privacy: .public) as \(kind.rawValue, privacy: .public)")
            onCapture?(item)
        } catch {
            log.error("couldn't shelve \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
