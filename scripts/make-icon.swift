import AppKit

// Draws the app icon at 1024×1024 into the path given as the first argument.
// Run via scripts/make-icon.sh, which slices it into the asset catalog.
//
// The picture: a black shelf hanging from the notch, holding screenshots, with
// one being dragged out by the pointer. That is the whole app in one gesture.

let size: CGFloat = 1024
let inset: CGFloat = 100
let side = size - inset * 2
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not allocate bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: Background squircle

let body = NSRect(x: inset, y: inset, width: side, height: side)
let squircle = NSBezierPath(roundedRect: body, xRadius: side * 0.2237, yRadius: side * 0.2237)

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [rgb(0x5B5BFF), rgb(0xA24BF0), rgb(0xFF6A88)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
    .draw(in: body, angle: -60)
// A soft glow under the notch, as if the shelf were lit from inside.
NSGradient(colors: [rgb(0xFFFFFF, 0.32), rgb(0xFFFFFF, 0)])?
    .draw(fromCenter: NSPoint(x: body.midX, y: body.maxY), radius: 0,
          toCenter: NSPoint(x: body.midX, y: body.maxY), radius: side * 0.62, options: [])

// MARK: The shelf hanging from the notch

let shelfWidth = side * 0.80
let shelfHeight = side * 0.40
let flare: CGFloat = 30
let bottomRadius: CGFloat = 72
let shelfTop = body.maxY
let shelfLeft = body.midX - shelfWidth / 2
let shelfRight = body.midX + shelfWidth / 2
let shelfBottom = shelfTop - shelfHeight

let shelf = NSBezierPath()
shelf.move(to: NSPoint(x: shelfLeft, y: shelfTop))
shelf.curve(to: NSPoint(x: shelfLeft + flare, y: shelfTop - flare),
            controlPoint1: NSPoint(x: shelfLeft + flare * 0.6, y: shelfTop),
            controlPoint2: NSPoint(x: shelfLeft + flare, y: shelfTop - flare * 0.4))
shelf.line(to: NSPoint(x: shelfLeft + flare, y: shelfBottom + bottomRadius))
shelf.curve(to: NSPoint(x: shelfLeft + flare + bottomRadius, y: shelfBottom),
            controlPoint1: NSPoint(x: shelfLeft + flare, y: shelfBottom + bottomRadius * 0.45),
            controlPoint2: NSPoint(x: shelfLeft + flare + bottomRadius * 0.45, y: shelfBottom))
shelf.line(to: NSPoint(x: shelfRight - flare - bottomRadius, y: shelfBottom))
shelf.curve(to: NSPoint(x: shelfRight - flare, y: shelfBottom + bottomRadius),
            controlPoint1: NSPoint(x: shelfRight - flare - bottomRadius * 0.45, y: shelfBottom),
            controlPoint2: NSPoint(x: shelfRight - flare, y: shelfBottom + bottomRadius * 0.45))
shelf.line(to: NSPoint(x: shelfRight - flare, y: shelfTop - flare))
shelf.curve(to: NSPoint(x: shelfRight, y: shelfTop),
            controlPoint1: NSPoint(x: shelfRight - flare, y: shelfTop - flare * 0.4),
            controlPoint2: NSPoint(x: shelfRight - flare * 0.6, y: shelfTop))
shelf.close()

NSGraphicsContext.saveGraphicsState()
let shelfShadow = NSShadow()
shelfShadow.shadowColor = rgb(0x1A0033, 0.55)
shelfShadow.shadowBlurRadius = 46
shelfShadow.shadowOffset = NSSize(width: 0, height: -22)
shelfShadow.set()
rgb(0x0B0B12).setFill()
shelf.fill()
NSGraphicsContext.restoreGraphicsState()

// The camera, a dot at the top of the notch.
let cameraCenter = NSPoint(x: body.midX, y: shelfTop - 34)
rgb(0x1F2033).setFill()
NSBezierPath(ovalIn: NSRect(x: cameraCenter.x - 11, y: cameraCenter.y - 11, width: 22, height: 22)).fill()
rgb(0x5A7BFF, 0.8).setFill()
NSBezierPath(ovalIn: NSRect(x: cameraCenter.x - 4, y: cameraCenter.y + 1, width: 6, height: 6)).fill()

// MARK: Screenshot cards

/// A tiny "screenshot": a white-framed photo of a sun over hills.
func drawCard(center: NSPoint, width: CGFloat, rotation: CGFloat, palette: (sky: [UInt32], hill: UInt32, hill2: UInt32), shadow: Bool) {
    let height = width * 0.66
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation * .pi / 180)
    let frame = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let card = NSBezierPath(roundedRect: frame, xRadius: width * 0.09, yRadius: width * 0.09)

    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = rgb(0x000000, 0.45)
        s.shadowBlurRadius = 34
        s.shadowOffset = NSSize(width: 0, height: -18)
        s.set()
        rgb(0xFFFFFF).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    rgb(0xFFFFFF).setFill()
    card.fill()

    let photoRect = frame.insetBy(dx: width * 0.06, dy: width * 0.06)
    let photo = NSBezierPath(roundedRect: photoRect, xRadius: width * 0.05, yRadius: width * 0.05)
    NSGraphicsContext.saveGraphicsState()
    photo.addClip()
    NSGradient(colors: palette.sky.map { rgb($0) })?.draw(in: photoRect, angle: -90)
    // Sun
    let sunR = photoRect.height * 0.16
    rgb(0xFFE36E).setFill()
    NSBezierPath(ovalIn: NSRect(x: photoRect.maxX - photoRect.width * 0.3 - sunR, y: photoRect.maxY - photoRect.height * 0.3 - sunR,
                                width: sunR * 2, height: sunR * 2)).fill()
    // Hills
    let back = NSBezierPath()
    back.move(to: NSPoint(x: photoRect.minX, y: photoRect.minY))
    back.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.38, y: photoRect.minY + photoRect.height * 0.62))
    back.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.78, y: photoRect.minY))
    back.close()
    rgb(palette.hill2).setFill()
    back.fill()
    let front = NSBezierPath()
    front.move(to: NSPoint(x: photoRect.minX + photoRect.width * 0.35, y: photoRect.minY))
    front.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.7, y: photoRect.minY + photoRect.height * 0.45))
    front.line(to: NSPoint(x: photoRect.maxX + photoRect.width * 0.05, y: photoRect.minY))
    front.close()
    rgb(palette.hill).setFill()
    front.fill()
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

let cardWidth = shelfWidth * 0.25
let cardY = shelfTop - shelfHeight * 0.60
let slotXs = [body.midX - shelfWidth * 0.29, body.midX, body.midX + shelfWidth * 0.29]

drawCard(center: NSPoint(x: slotXs[0], y: cardY), width: cardWidth, rotation: 0,
         palette: ([0x8FD8FF, 0x5A8CFF], 0x2E9D7A, 0x7ACF9F), shadow: false)
drawCard(center: NSPoint(x: slotXs[2], y: cardY), width: cardWidth, rotation: 0,
         palette: ([0xFFC18A, 0xFF7A9C], 0x7A3FB0, 0xB57BE0), shadow: false)

// The empty slot the dragged card came from.
let slot = NSRect(x: slotXs[1] - cardWidth / 2, y: cardY - cardWidth * 0.33, width: cardWidth, height: cardWidth * 0.66)
let slotPath = NSBezierPath(roundedRect: slot, xRadius: cardWidth * 0.09, yRadius: cardWidth * 0.09)
slotPath.lineWidth = 7
slotPath.setLineDash([22, 14], count: 2, phase: 0)
rgb(0xFFFFFF, 0.35).setStroke()
slotPath.stroke()

// The card on its way out, bigger and tilted, half over the shelf's edge.
let draggedCenter = NSPoint(x: body.midX + side * 0.06, y: shelfBottom - side * 0.10)
drawCard(center: draggedCenter, width: cardWidth * 1.45, rotation: -9,
         palette: ([0x9BE7FF, 0x6C6BFF], 0x1F8F8A, 0x63D2B4), shadow: true)

// MARK: Pointer

let tip = NSPoint(x: draggedCenter.x + cardWidth * 0.42, y: draggedCenter.y - cardWidth * 0.18)
let s: CGFloat = 4.2
let pointer = NSBezierPath()
let points: [(CGFloat, CGFloat)] = [(0, 0), (0, -34), (8, -26), (14, -40), (20, -37), (14, -24), (25, -24)]
for (i, p) in points.enumerated() {
    let point = NSPoint(x: tip.x + p.0 * s, y: tip.y + p.1 * s)
    if i == 0 { pointer.move(to: point) } else { pointer.line(to: point) }
}
pointer.close()
pointer.lineJoinStyle = .round
NSGraphicsContext.saveGraphicsState()
let pointerShadow = NSShadow()
pointerShadow.shadowColor = rgb(0x000000, 0.4)
pointerShadow.shadowBlurRadius = 14
pointerShadow.shadowOffset = NSSize(width: 0, height: -6)
pointerShadow.set()
rgb(0x111111).setFill()
pointer.fill()
NSGraphicsContext.restoreGraphicsState()
pointer.lineWidth = 9
rgb(0xFFFFFF).setStroke()
pointer.stroke()
rgb(0x111111).setFill()
pointer.fill()

NSGraphicsContext.restoreGraphicsState()  // squircle clip
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
