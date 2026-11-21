import XCTest
@testable import ShelfCore

final class CaptureClassifierTests: XCTestCase {
    func classify(_ name: String, tagged: Bool = false) -> ShelfItem.Source? {
        CaptureClassifier.classify(fileName: name, isTaggedScreenCapture: tagged)
    }

    func testHiddenTempFilesAreIgnored() {
        XCTAssertNil(classify(".Screenshot 2026-11-21 at 10.00.00.png", tagged: true))
    }

    func testTaggedImageIsAScreenshotWhateverItsName() {
        XCTAssertEqual(classify("Bildschirmfoto 2026-11-21.png", tagged: true), .screenshot)
    }

    func testEnglishNamesAreRecognisedWithoutTheTag() {
        XCTAssertEqual(classify("Screenshot 2026-11-21 at 10.00.00 AM.png"), .screenshot)
        XCTAssertEqual(classify("Screen Recording 2026-11-21 at 10.00.00 AM.mov"), .screenRecording)
    }

    func testTaggedVideoIsARecording() {
        XCTAssertEqual(classify("Aufnahme.mov", tagged: true), .screenRecording)
    }

    func testSimulatorCaptures() {
        XCTAssertEqual(classify("Simulator Screenshot - iPhone 17 Pro - 2026-11-21 at 10.00.00.png"), .simulatorScreenshot)
        XCTAssertEqual(classify("Simulator Screen Recording - iPhone 17 Pro - 2026-11-21 at 10.00.00.mp4"), .simulatorRecording)
    }

    func testUnrelatedFilesAreLeftAlone() {
        XCTAssertNil(classify("holiday.png"))
        XCTAssertNil(classify("notes.txt", tagged: true))
        XCTAssertNil(classify("Screenshot list.txt"))
    }
}
