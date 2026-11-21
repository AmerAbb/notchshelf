import AppKit
import ShelfCore
import SwiftUI

/// Sits over each thumbnail and handles the mouse in AppKit: click, ⌘-click,
/// right-click, and dragging out. SwiftUI's drag support carries one item and
/// can't say when a drag ends; this can drag the whole selection and keeps the
/// shelf open until the drop.
final class ItemInteractionView: NSView, NSDraggingSource {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDragStateChange: ((Bool) -> Void)?
    var dragPayload: (() -> [(url: URL, image: NSImage?)])?
    var menuProvider: (() -> NSMenu?)?

    private var mouseDownPoint: NSPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 3,
              let payload = dragPayload?(), !payload.isEmpty
        else { return }
        isDragging = true

        let items = payload.enumerated().map { index, entry -> NSDraggingItem in
            // A proper file URL, not a path string: chat apps then receive
            // the file itself.
            let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
            let offset = CGFloat(index) * 6
            item.setDraggingFrame(
                bounds.offsetBy(dx: offset, dy: -offset),
                contents: entry.image ?? NSWorkspace.shared.icon(forFile: entry.url.path)
            )
            return item
        }
        onDragStateChange?(true)
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging, mouseDownPoint != nil { onClick?(event.modifierFlags) }
        mouseDownPoint = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy out to other apps; never onto our own shelf.
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownPoint = nil
        onDragStateChange?(false)
    }
}

struct ItemInteraction: NSViewRepresentable {
    let item: ShelfItem
    let model: NotchModel

    func makeNSView(context: Context) -> ItemInteractionView {
        let view = ItemInteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ItemInteractionView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ItemInteractionView) {
        let item = item, model = model
        view.onClick = { modifiers in model.click(item, modifiers: modifiers) }
        view.onHover = { inside in
            if inside {
                model.hoveredID = item.id
            } else if model.hoveredID == item.id {
                model.hoveredID = nil
            }
        }
        view.onDragStateChange = { model.isDraggingOut = $0 }
        view.dragPayload = {
            model.targets(for: item).map { (url: model.url($0), image: model.thumbnail($0)) }
        }
        view.menuProvider = { model.contextMenu(for: item) }
    }
}
