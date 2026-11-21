import AppKit
import Quartz

/// The borderless window that hangs from the notch. It is always on screen and
/// mostly transparent; while the shelf is closed it ignores the mouse entirely
/// so clicks fall through to the menu bar beneath.
final class NotchPanel: NSPanel {
    /// Gets first look at key presses; return true to swallow one.
    var keyHandler: ((NSEvent) -> Bool)?
    weak var previewSource: PreviewSource?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, so the shelf can grow out of the real notch.
        // (Don't set isFloatingPanel: it quietly resets the level to
        // .floating, which macOS keeps below the menu bar, and the shelf
        // then hangs under the notch instead of from it.)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Keep the shelf out of the screenshots it collects.
        sharingType = .none
    }

    // Key only so Space (Quick Look), Esc and ⌘C reach us while the shelf is
    // open. Non-activating, so the app you were using stays the active app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS nudges windows out from under the menu bar; this one belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = previewSource
        panel.delegate = previewSource
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

final class PreviewSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []
    var onClose: (() -> Void)?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Lends the app focus for a moment (Quick Look, the blur editor) and hands it
/// back to whatever you were using afterwards.
@MainActor
enum Focus {
    private static var previous: NSRunningApplication?

    static func take() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previous = front
        }
        NSApp.activate()
    }

    static func giveBack() {
        guard let app = previous else { return }
        previous = nil
        app.activate()
    }
}
