import AppKit
import Observation
import QuickLookThumbnailing
import ShelfCore
import UniformTypeIdentifiers

enum NotchMode: Equatable {
    /// Just the notch.
    case hidden
    /// A thumbnail wing either side of the notch for a moment, after a capture
    /// lands or the latest one is copied.
    case peek
    /// The full shelf.
    case expanded
}

/// Everything the notch UI shows and every action it can take.
@MainActor @Observable
final class NotchModel {
    let store: ShelfStore
    let thumbnails = ThumbnailCache()

    var mode: NotchMode = .hidden
    var geometry = NotchGeometry(notchRect: CGRect(x: 0, y: 0, width: 200, height: 32), hasPhysicalNotch: false)
    var peekItemID: UUID?
    var peekLabel = ""
    var selection: Set<UUID> = []
    var hoveredID: UUID?
    var flashID: UUID?
    var flashText = ""
    var isDropTargeted = false

    /// One of our own items is being dragged out (the shelf stays open).
    var isDraggingOut = false
    @ObservationIgnored var onQuickLook: (() -> Void)?
    @ObservationIgnored var onRedact: ((ShelfItem) -> Void)?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    static let peekEar: CGFloat = 74
    static let cellSize = CGSize(width: 116, height: 76)

    init(store: ShelfStore) {
        self.store = store
    }

    var items: [ShelfItem] { store.items }
    var notchSize: CGSize { geometry.notchRect.size }
    var expandedSize: CGSize {
        CGSize(width: max(notchSize.width + 460, 660), height: notchSize.height + 146)
    }

    func url(_ item: ShelfItem) -> URL { store.url(for: item) }

    func thumbnail(_ item: ShelfItem) -> NSImage? {
        thumbnails.image(for: item.fileName, url: store.url(for: item))
    }

    // MARK: Peek

    func peek(_ item: ShelfItem, label: String) {
        guard mode != .expanded else { return }
        peekItemID = item.id
        peekLabel = label
        mode = .peek
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self, self.mode == .peek else { return }
            self.mode = .hidden
        }
    }

    // MARK: Which items an action applies to

    /// Acting on a selected item acts on the whole selection.
    func targets(for item: ShelfItem) -> [ShelfItem] {
        guard selection.contains(item.id), selection.count > 1 else { return [item] }
        return items.filter { selection.contains($0.id) }
    }

    /// For Space, ⌘C and Delete: the selection, else the hovered item, else
    /// the newest.
    func keyboardTargets() -> [ShelfItem] {
        if !selection.isEmpty { return items.filter { selection.contains($0.id) } }
        if let id = hoveredID, let item = store.item(id) { return [item] }
        return items.first.map { [$0] } ?? []
    }

    // MARK: Actions

    func click(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else if modifiers.contains(.option) {
            copyPaths(targets(for: item))
        } else {
            selection.removeAll()
            copy([item])
        }
    }

    func copy(_ items: [ShelfItem]) {
        Clipboard.copy(items.map(url))
        flash(items, items.count > 1 ? "Copied \(items.count)" : "Copied")
    }

    /// Paths escaped the way Terminal escapes a dropped file, so they paste
    /// straight into a shell or a Claude Code prompt.
    func copyPaths(_ items: [ShelfItem]) {
        Clipboard.copyText(items.map { Clipboard.shellEscaped(url($0).path) }.joined(separator: " "))
        flash(items, "Path copied")
    }

    func copyLatest() {
        guard let item = store.newest else {
            NSSound.beep()
            return
        }
        Clipboard.copy([url(item)])
        peek(item, label: "Copied")
    }

    func togglePin(_ item: ShelfItem) {
        store.setPinned(!item.pinned, for: item.id)
    }

    func remove(_ items: [ShelfItem]) {
        let ids = Set(items.map(\.id))
        store.remove(ids)
        selection.subtract(ids)
        if let hovered = hoveredID, ids.contains(hovered) { hoveredID = nil }
    }

    func clearAll() {
        store.clear()
        selection.removeAll()
    }

    func showInFinder(_ items: [ShelfItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(url))
    }

    private func flash(_ items: [ShelfItem], _ text: String) {
        flashID = items.first?.id
        flashText = text
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            self?.flashID = nil
        }
    }

    // MARK: Dropping files onto the notch

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.park(url) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage,
                          let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                    else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.park(png) }
                    }
                }
            }
        }
        return accepted
    }

    /// Dropping something that's already on the shelf (an item dragged out
    /// and straight back, or a copy of one) doesn't add it again; the item
    /// that's there says so instead.
    private func park(_ url: URL) {
        if let existing = store.existingItem(matching: url) {
            flash([existing], "Already here")
            return
        }
        _ = try? store.ingest(fileAt: url, as: .dropped, move: false)
    }

    private func park(_ png: Data) {
        if let existing = store.existingItem(matching: png) {
            flash([existing], "Already here")
            return
        }
        _ = try? store.ingest(data: png, suggestedName: "Dropped image.png")
    }

    // MARK: Context menu

    func contextMenu(for item: ShelfItem) -> NSMenu {
        let targets = targets(for: item)
        let many = targets.count > 1
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(many ? "Copy \(targets.count) Items" : "Copy", symbol: "doc.on.doc") { [weak self] in
            self?.copy(targets)
        })
        menu.addItem(ActionMenuItem(many ? "Copy Paths" : "Copy Path", symbol: "terminal") { [weak self] in
            self?.copyPaths(targets)
        })
        menu.addItem(ActionMenuItem("Quick Look", symbol: "eye") { [weak self] in
            self?.selection = Set(targets.map(\.id))
            self?.onQuickLook?()
        })
        if !many, item.kind == .image {
            menu.addItem(ActionMenuItem("Blur Part of It…", symbol: "checkerboard.rectangle") { [weak self] in
                self?.onRedact?(item)
            })
        }
        if !many {
            menu.addItem(ActionMenuItem(item.pinned ? "Unpin" : "Pin (Keep Past a Day)", symbol: item.pinned ? "pin.slash" : "pin") { [weak self] in
                self?.togglePin(item)
            })
        }
        menu.addItem(ActionMenuItem("Show in Finder", symbol: "folder") { [weak self] in
            self?.showInFinder(targets)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(many ? "Remove \(targets.count) Items" : "Remove", symbol: "trash") { [weak self] in
            self?.remove(targets)
        })
        return menu
    }
}

/// Thumbnails for shelf items, made by Quick Look so images, videos and any
/// other file type all get something sensible.
@MainActor @Observable
final class ThumbnailCache {
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    func image(for key: String, url: URL) -> NSImage? {
        if let image = images[key] { return image }
        load(key, url)
        return nil
    }

    private func load(_ key: String, _ url: URL) {
        guard !pending.contains(key) else { return }
        pending.insert(key)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 240, height: 160), scale: 2, representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.images[key] = image ?? NSWorkspace.shared.icon(forFile: url.path)
                    self.pending.remove(key)
                }
            }
        }
    }
}

enum Clipboard {
    /// One image goes on the clipboard as both the file and its pixels, so
    /// ⌘V works in chat apps and image editors alike (and in Finder, as the
    /// file). Several items go on as files.
    static func copy(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard urls.count == 1, let url = urls.first else {
            pasteboard.writeObjects(urls.map { $0 as NSURL })
            return
        }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let png = pngData(for: url) { item.setData(png, forType: .png) }
        pasteboard.writeObjects([item])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func shellEscaped(_ path: String) -> String {
        let special = Set(" \\'\"()[]{}&;|<>*?!$`#~")
        return path.map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    private static func pngData(for url: URL) -> Data? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return nil }
        if type.conforms(to: .png) { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

/// An NSMenuItem that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
