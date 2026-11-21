import AppKit
import Quartz
import ShelfCore
import SwiftUI

/// Owns the notch panel and decides when the shelf opens and closes.
///
/// Hover is detected by polling the pointer position rather than through
/// tracking areas: the panel ignores the mouse while closed (so it never blocks
/// the menu bar), and polling also sees drags coming from other apps, which
/// deliver no mouse events to us at all. Reading the pointer needs no
/// Accessibility permission.
@MainActor
final class NotchController: NSObject {
    let model: NotchModel
    private let panel = NotchPanel()
    private let previewSource = PreviewSource()
    private var pollTimer: Timer?
    private var clickMonitor: Any?

    private var hoverStartedAt: Date?
    private var lastInsideAt = Date()
    /// After closing by hand (Esc) while the pointer is still over the notch,
    /// don't reopen until it has left.
    private var suppressUntilPointerLeaves = false
    /// Opened from the menu bar: stay open until the pointer has visited and
    /// left, or you click elsewhere.
    private var openedFromMenu = false
    private var dragChangeCountAtMouseDown: Int?

    /// How long the pointer must rest on the notch before the shelf opens.
    /// Brushing past on the way to a menu shouldn't open it.
    private let openDelay: TimeInterval = 0.12
    private let closeGrace: TimeInterval = 0.3

    init(model: NotchModel) {
        self.model = model
        super.init()

        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.previewSource = previewSource
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        previewSource.onClose = { Focus.giveBack() }
        model.onQuickLook = { [weak self] in self?.toggleQuickLook() }

        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        // Default run loop mode on purpose: polling pauses while a context
        // menu or one of our own drags is tracking, so neither can close the
        // shelf out from under itself.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .default)
        pollTimer = timer

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedElsewhere() }
        }
    }

    // MARK: Geometry

    /// The built-in display if it has a notch, else the main display.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    @objc private func screensChanged() { layout() }

    private func layout() {
        guard let screen = targetScreen else { return }
        model.geometry = NotchGeometry.compute(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        // Room around the open shelf for its shadow.
        let size = model.expandedSize
        let width = size.width + 80, height = size.height + 40
        let notch = model.geometry.notchRect
        panel.setFrame(
            NSRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height),
            display: true
        )
    }

    private var expandedRect: CGRect {
        let size = model.expandedSize, notch = model.geometry.notchRect
        return CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
    }

    /// The closed notch, a little wider, reaching to the very top pixel row.
    private var closedZone: CGRect {
        let notch = model.geometry.notchRect
        let extraWidth: CGFloat = model.mode == .peek ? NotchModel.peekEar + 6 : 6
        return CGRect(x: notch.minX - extraWidth, y: notch.minY, width: notch.width + extraWidth * 2, height: notch.height + 2)
    }

    // MARK: Opening and closing

    private func tick() {
        let pointer = NSEvent.mouseLocation
        let now = Date()

        switch model.mode {
        case .hidden, .peek:
            let fileDrag = isFileDragInProgress()
            // A drag gets a more generous target: aiming while dragging is harder.
            let zone = fileDrag ? closedZone.insetBy(dx: -40, dy: -30) : closedZone
            guard zone.contains(pointer) else {
                hoverStartedAt = nil
                suppressUntilPointerLeaves = false
                return
            }
            guard !suppressUntilPointerLeaves else { return }
            let started = hoverStartedAt ?? now
            hoverStartedAt = started
            if fileDrag || now.timeIntervalSince(started) >= openDelay {
                expand()
            }

        case .expanded:
            if expandedRect.insetBy(dx: -14, dy: -14).contains(pointer) {
                lastInsideAt = now
                openedFromMenu = false
                return
            }
            let busy = openedFromMenu || model.isDraggingOut || isQuickLookVisible
            if !busy, now.timeIntervalSince(lastInsideAt) > closeGrace {
                collapse()
            }
        }
    }

    /// True while something carrying files or images is being dragged. A new
    /// drag bumps the drag pasteboard's change count; checking the types too
    /// means dragging a browser tab or a window past the notch doesn't count.
    private func isFileDragInProgress() -> Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            dragChangeCountAtMouseDown = nil
            return false
        }
        let pasteboard = NSPasteboard(name: .drag)
        guard let atMouseDown = dragChangeCountAtMouseDown else {
            dragChangeCountAtMouseDown = pasteboard.changeCount
            return false
        }
        guard pasteboard.changeCount != atMouseDown, let types = pasteboard.types else { return false }
        return types.contains(.fileURL) || types.contains(.png) || types.contains(.tiff)
    }

    private var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func expand() {
        guard model.mode != .expanded else { return }
        model.mode = .expanded
        lastInsideAt = Date()
        hoverStartedAt = nil
        panel.ignoresMouseEvents = false
        panel.makeKey()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func collapse(byHand: Bool = false) {
        guard model.mode == .expanded else { return }
        model.mode = .hidden
        model.selection.removeAll()
        model.hoveredID = nil
        model.isDropTargeted = false
        openedFromMenu = false
        suppressUntilPointerLeaves = byHand
        panel.ignoresMouseEvents = true
        returnKeyFocusAfterAnimation()
    }

    /// Hands keyboard focus back to the app you were in. Ordering a
    /// non-activating panel out and back in is the reliable way, but doing it
    /// straight away hides the window mid-animation and the shelf just
    /// vanishes, so wait for the shrink to finish first.
    private func returnKeyFocusAfterAnimation() {
        guard panel.isKeyWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.mode != .expanded, self.panel.isKeyWindow,
                      !self.isQuickLookVisible
                else { return }
                self.panel.orderOut(nil)
                self.panel.orderFrontRegardless()
            }
        }
    }

    /// From the menu bar or the hotkey: open without hovering.
    func showShelf() {
        expand()
        openedFromMenu = true
    }

    private func clickedElsewhere() {
        guard model.mode == .expanded, !isQuickLookVisible else { return }
        if !expandedRect.contains(NSEvent.mouseLocation) { collapse() }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command) {
        case (49, false):  // Space
            toggleQuickLook()
        case (53, _):  // Esc
            collapse(byHand: true)
        case (8, true):  // ⌘C
            let targets = model.keyboardTargets()
            guard !targets.isEmpty else { return false }
            model.copy(targets)
        case (0, true):  // ⌘A
            model.selection = Set(model.items.map(\.id))
        case (51, _), (117, _):  // Delete, Forward Delete
            model.remove(model.keyboardTargets())
        default:
            return false
        }
        return true
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if isQuickLookVisible {
            panel.orderOut(nil)
            return
        }
        let urls = model.keyboardTargets().map(model.url)
        guard !urls.isEmpty else { return }
        previewSource.urls = urls
        // Quick Look needs the app active to take keyboard focus (so Space
        // closes it again); focus is handed back when it closes.
        Focus.take()
        self.panel.makeKey()
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    // MARK: Demo

    /// `-demoMode expanded|peek` on the command line, for screenshots of the UI.
    func demo(_ mode: String) {
        // Normally the panel hides from screen capture; a demo is for capturing.
        panel.sharingType = .readOnly
        switch mode {
        case "expanded": showShelf()
        case "hover":
            showShelf()
            model.hoveredID = model.items.first?.id
        case "peek": if let item = model.items.first { model.peek(item, label: "Shelved") }
        case "collapse":
            // Open, then close after a second; snapshotDelay counts from the close.
            showShelf()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { self?.collapse() }
            }
        default: break
        }
        // `-snapshotPath <png>`: render the panel to a file once the animation
        // settles, then quit. Lets the UI be checked without screen recording
        // permission.
        if let path = UserDefaults.standard.string(forKey: "snapshotPath") {
            let defaults = UserDefaults.standard
            var delay = defaults.object(forKey: "snapshotDelay") == nil ? 1.2 : defaults.double(forKey: "snapshotDelay")
            if mode == "collapse" { delay += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    self?.snapshot(to: path)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func snapshot(to path: String) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
