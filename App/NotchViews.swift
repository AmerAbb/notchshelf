import ShelfCore
import SwiftUI

/// The notch silhouette: square top that flares out into the menu bar, rounded
/// bottom corners. Both radii animate, so the shape grows smoothly out of the
/// hardware notch.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = max(0, min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct NotchRootView: View {
    @Bindable var model: NotchModel

    /// The black shape grows out of the notch; content follows once there is
    /// room for it, and leaves first on the way back.
    private static let grow = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Closing is quicker and doesn't bounce: it should settle back into the
    /// notch, not wobble.
    private static let shrink = Animation.spring(response: 0.32, dampingFraction: 0.95)
    private static let contentIn = AnyTransition.opacity
        .combined(with: .scale(scale: 0.94, anchor: .top))
        .combined(with: .offset(y: -6))
        .animation(.spring(response: 0.34, dampingFraction: 0.85).delay(0.1))
    private static let contentOut = AnyTransition.opacity.animation(.easeOut(duration: 0.1))

    var body: some View {
        let size = shapeSize
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        ZStack(alignment: .top) {
            // Closed, this sits exactly over the hardware notch, black on
            // black, so opening reads as the notch itself growing. Screens
            // without a notch have nothing to grow from, so there it fades.
            shape
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.mode == .expanded ? 0.45 : 0), radius: 14, y: 6)
                .opacity(model.mode == .hidden && !model.geometry.hasPhysicalNotch ? 0 : 1)

            ZStack(alignment: .top) {
                switch model.mode {
                case .hidden:
                    EmptyView()
                case .peek:
                    PeekView(model: model, inset: topRadius + 10)
                        .transition(.asymmetric(insertion: Self.contentIn, removal: Self.contentOut))
                case .expanded:
                    ShelfView(model: model, inset: topRadius + 18)
                        .transition(.asymmetric(insertion: Self.contentIn, removal: Self.contentOut))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.mode == .hidden ? Self.shrink : Self.grow, value: model.mode)
        .environment(\.colorScheme, .dark)
    }

    private var topRadius: CGFloat {
        switch model.mode {
        case .hidden: 0
        case .peek: 6
        case .expanded: 12
        }
    }

    private var bottomRadius: CGFloat { model.mode == .expanded ? 24 : 10 }

    private var shapeSize: CGSize {
        let notch = model.notchSize
        switch model.mode {
        // A touch smaller than the hardware notch, so the closed shape is
        // always fully behind it whatever its exact corner radius.
        case .hidden: return CGSize(width: notch.width - 6, height: notch.height - 2)
        case .peek: return CGSize(width: notch.width + 2 * NotchModel.peekEar + 12, height: notch.height)
        case .expanded: return model.expandedSize
        }
    }
}

/// The wings either side of the notch that briefly confirm a capture landed.
struct PeekView: View {
    let model: NotchModel
    let inset: CGFloat

    var body: some View {
        let item = model.peekItemID.flatMap(model.store.item)
        HStack(spacing: 0) {
            Group {
                if let item, let image = model.thumbnail(item) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.12)
                }
            }
            .frame(width: NotchModel.peekEar - 24, height: max(14, model.notchSize.height - 12))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(model.peekLabel)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, inset)
    }
}

struct ShelfView: View {
    @Bindable var model: NotchModel
    let inset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: model.notchSize.height)

            Group {
                if model.items.isEmpty {
                    EmptyShelf()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(model.items) { item in
                                ThumbnailCell(item: item, model: model)
                            }
                        }
                        .padding(.horizontal, inset)
                        .padding(.top, 10)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text("Click to copy · drag out · ⌥-click copies path · ⌘-click selects · Space previews")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.bottom, 10)
        }
        .overlay {
            if model.isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    Label(
                        model.isDraggingOut ? "Drop to put it back" : "Drop to park it until tomorrow",
                        systemImage: model.isDraggingOut ? "arrow.uturn.backward" : "tray.and.arrow.down"
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, inset - 6)
                .padding(.top, model.notchSize.height + 4)
                .padding(.bottom, 10)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
            model.acceptDrop(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                Text("Shelf").fontWeight(.semibold)
                if !model.items.isEmpty {
                    Text("\(model.items.count)").foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: model.notchSize.width + 20)

            HStack(spacing: 12) {
                if !model.selection.isEmpty {
                    Text("\(model.selection.count) selected").foregroundStyle(.white.opacity(0.6))
                    HeaderButton(symbol: "xmark.circle", help: "Deselect") { model.selection.removeAll() }
                }
                HeaderButton(symbol: "trash", help: "Clear the shelf (pinned items stay)") { model.clearAll() }
                    .disabled(model.items.isEmpty)
                    .opacity(model.items.isEmpty ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, inset)
    }
}

struct EmptyShelf: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            Text("Screenshots land here")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Take one with ⇧⌘4, or drop any file here to park it until tomorrow")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ThumbnailCell: View {
    let item: ShelfItem
    @Bindable var model: NotchModel
    @State private var captionHovered = false
    /// Lags the pointer slightly on the way out, so crossing from the
    /// thumbnail to the caption's buttons doesn't flick them off and on.
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    private var size: CGSize { NotchModel.cellSize }

    var body: some View {
        let selected = model.selection.contains(item.id)
        let hovered = model.hoveredID == item.id

        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                thumbnail
                badges
                if model.flashID == item.id {
                    ZStack {
                        Color.black.opacity(0.6)
                        Label(model.flashText, systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.14), lineWidth: selected ? 2.5 : 1)
            )
            .scaleEffect(hovered ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.15), value: model.flashID)
            // Outside the scale, so the AppKit view tracking the pointer keeps
            // a fixed frame while the thumbnail grows under it.
            .overlay(ItemInteraction(item: item, model: model))

            captionRow
                // The gap above belongs to the caption, so there's no dead
                // strip between the thumbnail and the buttons.
                .padding(.top, 5)
                .frame(width: size.width, height: 19)
                .contentShape(Rectangle())
                .onHover { captionHovered = $0 }
        }
        .onChange(of: hovered || captionHovered, initial: true) { _, active in
            hideTask?.cancel()
            if active {
                showControls = true
            } else {
                hideTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    showControls = false
                }
            }
        }
    }

    /// The time (or file name) with the item's buttons laid over its end.
    /// The text keeps the same width whether or not the buttons show, so
    /// hovering never makes it re-truncate and jump.
    private var captionRow: some View {
        ZStack(alignment: .trailing) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(caption(now: context.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A pinned item always shows its pin; leave it room.
                    .padding(.trailing, item.pinned ? 20 : 0)
            }

            HStack(spacing: 7) {
                if showControls {
                    if item.kind == .image {
                        CellButton(symbol: "checkerboard.rectangle", help: "Blur part of it") { model.onRedact?(item) }
                    }
                    CellButton(symbol: "xmark", help: "Remove") { model.remove([item]) }
                }
                if showControls || item.pinned {
                    CellButton(symbol: item.pinned ? "pin.fill" : "pin", help: item.pinned ? "Unpin" : "Pin: keep past today") {
                        model.togglePin(item)
                    }
                }
            }
            .padding(.leading, 22)
            .background {
                // Fade the end of a long name out under the buttons.
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.35)],
                               startPoint: .leading, endPoint: .trailing)
                    .opacity(showControls ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: showControls)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        ZStack {
            Color.white.opacity(0.07)
            if let image = model.thumbnail(item) {
                if item.kind == .other {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(12)
                } else {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private var badges: some View {
        VStack {
            HStack {
                if item.isFromSimulator { Badge(symbol: "iphone") }
                Spacer()
                if item.pinned { Badge(symbol: "pin.fill") }
            }
            Spacer()
            HStack {
                if item.kind == .video { Badge(symbol: "play.fill") }
                Spacer()
            }
        }
        .padding(5)
    }

    private func caption(now: Date) -> String {
        item.source == .dropped ? item.fileName : RelativeTime.short(item.addedAt, now: now)
    }
}

struct Badge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(.black.opacity(0.55), in: Circle())
    }
}

struct CellButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
