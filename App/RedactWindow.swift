import AppKit
import CoreImage
import ShelfCore
import SwiftUI

/// A small editor for pixelating parts of a screenshot before it goes
/// anywhere. Saving replaces the shelf item with the pixelated copy; the
/// original goes to the Trash.
@MainActor
final class RedactWindowController: NSObject, NSWindowDelegate {
    private static var open: [RedactWindowController] = []

    private let window: NSWindow
    private let item: ShelfItem
    private let store: ShelfStore
    private let source: CIImage

    static func present(item: ShelfItem, store: ShelfStore) {
        let url = store.url(for: item)
        guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            NSSound.beep()
            return
        }
        let controller = RedactWindowController(item: item, store: store, source: source)
        open.append(controller)
        Focus.take()
        controller.window.makeKeyAndOrderFront(nil)
    }

    private init(item: ShelfItem, store: ShelfStore, source: CIImage) {
        self.item = item
        self.store = store
        self.source = source

        // Screenshots are 2× pixels; show them at roughly point size, capped.
        let points = CGSize(width: source.extent.width / 2, height: source.extent.height / 2)
        let scale = min(1, 960 / points.width, 620 / points.height)
        let imageSize = CGSize(width: max(440, points.width * scale), height: max(240, points.height * scale))

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: imageSize.width + 32, height: imageSize.height + 84)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blur — \(item.fileName)"
        window.isReleasedWhenClosed = false
        super.init()

        window.delegate = self
        window.contentView = NSHostingView(rootView: RedactView(
            source: source,
            onSave: { [weak self] rects in self?.save(rects) },
            onCancel: { [weak self] in self?.window.close() }
        ))
        window.center()
    }

    private func save(_ rects: [CGRect]) {
        let output = Redactor.pixelate(source, normalizedRects: rects)
        guard let data = Redactor.pngData(output),
              (try? store.replaceContents(of: item.id, with: data, fileExtension: "png", suffix: "(blurred)")) != nil
        else {
            NSSound.beep()
            return
        }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
        Focus.giveBack()
    }
}

struct RedactView: View {
    let source: CIImage
    let onSave: ([CGRect]) -> Void
    let onCancel: () -> Void

    /// Normalised (0…1), top-left origin.
    @State private var rects: [CGRect] = []
    @State private var draft: CGRect?
    @State private var preview: NSImage?

    private static let context = CIContext()

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let fit = fittedSize(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    if let preview {
                        Image(nsImage: preview).resizable().frame(width: fit.width, height: fit.height)
                    }
                    ForEach(rects.indices, id: \.self) { index in
                        outline(rects[index], in: fit, dashed: false)
                    }
                    if let draft {
                        outline(draft, in: fit, dashed: true)
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                        .onChanged { value in
                            draft = normalized(from: value.startLocation, to: value.location, in: fit)
                        }
                        .onEnded { _ in
                            if let draft, draft.width > 0.004, draft.height > 0.004 {
                                rects.append(draft)
                                preview = render(rects)
                            }
                            draft = nil
                        }
                )
                .onHover { inside in
                    if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .padding(16)

            Divider()

            HStack {
                Text("Drag over anything sensitive to pixelate it.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Undo") {
                    rects.removeLast()
                    preview = render(rects)
                }
                .keyboardShortcut("z")
                .disabled(rects.isEmpty)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rects) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rects.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { preview = render([]) }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let image = source.extent.size
        guard image.width > 0, image.height > 0 else { return available }
        let scale = min(available.width / image.width, available.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func normalized(from start: CGPoint, to end: CGPoint, in size: CGSize) -> CGRect {
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
        }
        let a = clamp(start), b = clamp(end)
        return CGRect(
            x: min(a.x, b.x) / size.width,
            y: min(a.y, b.y) / size.height,
            width: abs(a.x - b.x) / size.width,
            height: abs(a.y - b.y) / size.height
        )
    }

    private func outline(_ rect: CGRect, in size: CGSize, dashed: Bool) -> some View {
        Rectangle()
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
            .frame(width: rect.width * size.width, height: rect.height * size.height)
            .offset(x: rect.minX * size.width, y: rect.minY * size.height)
    }

    private func render(_ rects: [CGRect]) -> NSImage? {
        let output = Redactor.pixelate(source, normalizedRects: rects)
        guard let image = Self.context.createCGImage(output, from: source.extent) else { return nil }
        return NSImage(cgImage: image, size: source.extent.size)
    }
}
