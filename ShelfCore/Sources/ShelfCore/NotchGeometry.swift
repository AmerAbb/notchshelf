import CoreGraphics

/// Where the notch is on a screen, in global screen coordinates (origin bottom
/// left, as AppKit measures).
public struct NotchGeometry: Equatable, Sendable {
    public var notchRect: CGRect
    /// False when the screen has no notch (an external display, or a MacBook
    /// with the lid closed); the shelf then hangs from a notch-sized spot at
    /// the top centre of the screen.
    public var hasPhysicalNotch: Bool

    public init(notchRect: CGRect, hasPhysicalNotch: Bool) {
        self.notchRect = notchRect
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    public static let fallbackWidth: CGFloat = 200

    /// - Parameters:
    ///   - leftArea, rightArea: `NSScreen.auxiliaryTopLeftArea` /
    ///     `auxiliaryTopRightArea`, the usable menu bar on either side of the
    ///     notch. Only their widths are used, which keeps this correct whether
    ///     or not they are reported relative to the screen.
    public static func compute(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        topInset: CGFloat,
        leftArea: CGRect?,
        rightArea: CGRect?
    ) -> NotchGeometry {
        if topInset > 0, let left = leftArea, let right = rightArea {
            let width = screenFrame.width - left.width - right.width
            if width > 0 {
                return NotchGeometry(
                    notchRect: CGRect(
                        x: screenFrame.minX + left.width,
                        y: screenFrame.maxY - topInset,
                        width: width,
                        height: topInset
                    ),
                    hasPhysicalNotch: true
                )
            }
        }
        let menuBar = screenFrame.maxY - visibleFrame.maxY
        let height = menuBar > 0 ? menuBar : 24
        return NotchGeometry(
            notchRect: CGRect(
                x: screenFrame.midX - fallbackWidth / 2,
                y: screenFrame.maxY - height,
                width: fallbackWidth,
                height: height
            ),
            hasPhysicalNotch: false
        )
    }
}
