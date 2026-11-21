import CoreImage
import XCTest
@testable import ShelfCore

final class NotchGeometryTests: XCTestCase {
    func testNotchedScreen() {
        // 14" MacBook Pro at default scaling.
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry.compute(
            screenFrame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            topInset: 38,
            leftArea: CGRect(x: 0, y: 944, width: 662, height: 38),
            rightArea: CGRect(x: 847, y: 944, width: 665, height: 38)
        )
        XCTAssertTrue(geometry.hasPhysicalNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 662, y: 944, width: 185, height: 38))
    }

    func testScreenWithoutANotchFallsBackToTheTopCentre() {
        let frame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry.compute(
            screenFrame: frame,
            visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
            topInset: 0, leftArea: nil, rightArea: nil
        )
        XCTAssertFalse(geometry.hasPhysicalNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 1512 + 1280 - 100, y: 1415, width: 200, height: 25))
    }
}

final class RedactorTests: XCTestCase {
    func testNormalisedRectFlipsToBottomLeftPixels() {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let rect = Redactor.pixelRect(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.25), in: extent)
        XCTAssertEqual(rect, CGRect(x: 100, y: 75, width: 100, height: 25))
    }

    func testRectsOutsideTheImageAreClipped() {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(Redactor.pixelRect(CGRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5), in: extent),
                       CGRect(x: 90, y: 0, width: 10, height: 10))
        XCTAssertEqual(Redactor.pixelRect(CGRect(x: 2, y: 2, width: 1, height: 1), in: extent), .zero)
    }

    /// Pixels inside the region change; pixels outside it don't.
    func testOnlyTheRegionIsPixelated() throws {
        let size = 128
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let original = try XCTUnwrap(context.createCGImage(noise, from: noise.extent))
        let source = CIImage(cgImage: original)

        // Top-left quarter, in on-screen terms.
        let output = Redactor.pixelate(source, normalizedRects: [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)])
        let rendered = try XCTUnwrap(context.createCGImage(output, from: source.extent))

        let before = try pixels(original), after = try pixels(rendered)
        func pixel(_ data: [UInt8], _ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let i = (y * size + x) * 4  // y measured from the top, like CGImage rows
            return data[i..<i + 4]
        }
        var changedInside = 0
        for y in 0..<size / 2 { for x in 0..<size / 2 where pixel(before, x, y) != pixel(after, x, y) { changedInside += 1 } }
        XCTAssertGreaterThan(changedInside, (size / 2) * (size / 2) / 2, "most of the region should change")
        for y in size / 2 + 1..<size { for x in 0..<size {
            XCTAssertEqual(pixel(before, x, y), pixel(after, x, y), "pixel (\(x),\(y)) outside the region changed")
        } }
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}
