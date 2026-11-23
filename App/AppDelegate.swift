import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ShelfCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ShelfStore!
    private var model: NotchModel!
    private var notch: NotchController!
    private var watcher: CaptureWatcher!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var sweepTimer: Timer?
    /// Sparkle only starts once a release key is configured (SUPublicEDKey in
    /// project.yml); before that it would fail loudly on every launch.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: AppDelegate.updatesConfigured, updaterDelegate: nil, userDriverDelegate: nil
    )

    static var updatesConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty && !key.hasPrefix("REPLACE")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notchshelf", isDirectory: true)
        store = ShelfStore(root: root)
        store.purgeExpired()

        model = NotchModel(store: store)
        model.onRedact = { [unowned self] item in
            RedactWindowController.present(item: item, store: store)
        }
        notch = NotchController(model: model)

        watcher = CaptureWatcher(store: store)
        watcher.onCapture = { [unowned self] item in
            model.peek(item, label: "Shelved")
        }
        refreshWatchedFolders()

        // ⌃⌥⌘V: copy the newest screenshot without opening anything.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey | cmdKey)) { [unowned self] in
            MainActor.assumeIsolated { model.copyLatest() }
        }

        setUpStatusItem()

        // Once a minute: sweep out anything a day old, and pick up a changed screenshot
        // folder (System Settings or ⇧⌘5 → Options → Save to).
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [unowned self] _ in
            MainActor.assumeIsolated { periodic() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [unowned self] _ in
            MainActor.assumeIsolated { periodic() }
        }

        if let demo = UserDefaults.standard.string(forKey: "demoMode") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [unowned self] in
                MainActor.assumeIsolated { notch.demo(demo) }
            }
        }
    }

    private func periodic() {
        store.purgeExpired()
        refreshWatchedFolders()
    }

    private func refreshWatchedFolders() {
        watcher.configure([
            .init(url: SystemPrefs.screenshotDirectory, accepts: [.screenshot, .screenRecording]),
            .init(url: SystemPrefs.simulatorDirectory, accepts: [.simulatorScreenshot, .simulatorRecording]),
        ])
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "notchshelf")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt each time it opens, so checkmarks and counts are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(ActionMenuItem("Show Shelf", symbol: "rectangle.topthird.inset.filled") { [unowned self] in
            notch.showShelf()
        })
        let copyLatest = ActionMenuItem("Copy Latest Screenshot", symbol: "doc.on.doc") { [unowned self] in
            model.copyLatest()
        }
        if hotKey != nil {
            copyLatest.keyEquivalent = "v"
            copyLatest.keyEquivalentModifierMask = [.control, .option, .command]
        }
        copyLatest.isEnabled = !store.items.isEmpty
        menu.addItem(copyLatest)

        menu.addItem(.separator())
        let unpinned = store.items.filter { !$0.pinned }.count
        let clear = ActionMenuItem("Clear Shelf (\(unpinned))", symbol: "trash") { [unowned self] in
            model.clearAll()
        }
        clear.isEnabled = unpinned > 0
        menu.addItem(clear)
        menu.addItem(ActionMenuItem("Open Shelf Folder", symbol: "folder") { [unowned self] in
            NSWorkspace.shared.open(store.directory)
        })

        menu.addItem(.separator())
        let skipPreview = ActionMenuItem("Skip macOS Screenshot Preview") {
            SystemPrefs.showsScreenshotThumbnail.toggle()
        }
        skipPreview.state = SystemPrefs.showsScreenshotThumbnail ? .off : .on
        skipPreview.toolTip = "While macOS shows its floating preview, a screenshot only reaches the shelf once the preview goes away (about 5 seconds)."
        menu.addItem(skipPreview)

        let login = ActionMenuItem("Open at Login") {
            let service = SMAppService.mainApp
            if service.status == .enabled { try? service.unregister() } else { try? service.register() }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        for location in watcher.locations {
            let path = (location.url.path as NSString).abbreviatingWithTildeInPath
            let what = location.accepts.contains(.screenshot) && location.accepts.contains(.simulatorScreenshot)
                ? "Screenshots & Simulator"
                : location.accepts.contains(.screenshot) ? "Screenshots" : "Simulator"
            let info = NSMenuItem(title: "\(what) from \(path)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())
        if Self.updatesConfigured {
            let updates = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            updates.target = updater
            menu.addItem(updates)
        }
        menu.addItem(ActionMenuItem("Quit notchshelf", key: "q") {
            NSApp.terminate(nil)
        })
    }
}
