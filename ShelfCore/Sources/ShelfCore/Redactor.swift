import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Pixelates regions of an image. Blocks are deliberately large: small blocks
/// over text can sometimes be reversed, big ones can't.
public enum Redactor {
    /// - Parameter normalizedRects: regions in 0…1 coordinates with a top-left
    ///   origin, the way they are drawn on screen.
    public static func pixelate(_ image: CIImage, normalizedRects: [CGRect]) -> CIImage {
        let extent = image.extent
        guard !normalizedRects.isEmpty, !extent.isEmpty, !extent.isInfinite else { return image }

        let filter = CIFilter.pixellate()
        filter.inputImage = image.clampedToExtent()
        filter.scale = Float(blockSize(for: extent))
        filter.center = CGPoint(x: extent.minX, y: extent.minY)
        guard let pixelated = filter.outputImage?.cropped(to: extent) else { return image }

        var result = image
        for rect in normalizedRects {
            let region = pixelRect(rect, in: extent)
            guard !region.isEmpty else { continue }
            result = pixelated.cropped(to: region).composited(over: result)
        }
        return result.cropped(to: extent)
    }

    static func blockSize(for extent: CGRect) -> CGFloat {
        max(16, min(extent.width, extent.height) / 30).rounded()
    }

    /// Converts a normalised, top-left-origin rect into the image's pixel
    /// space, which Core Image measures from the bottom left.
    public static func pixelRect(_ rect: CGRect, in extent: CGRect) -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clipped = rect.standardized.intersection(unit)
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(
            x: extent.minX + clipped.minX * extent.width,
            y: extent.minY + (1 - clipped.maxY) * extent.height,
            width: clipped.width * extent.width,
            height: clipped.height * extent.height
        ).integral
    }

    public static func pngData(_ image: CIImage, context: CIContext = CIContext()) -> Data? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.pngRepresentation(of: image, format: .RGBA8, colorSpace: space)
    }
}
