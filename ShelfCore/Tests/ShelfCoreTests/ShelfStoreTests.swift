import XCTest
@testable import ShelfCore

@MainActor
final class ShelfStoreTests: XCTestCase {
    var root: URL!
    var inbox: URL!
    var clock = Date()
    var discarded: [String] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString)")
        inbox = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        discarded = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func makeStore() -> ShelfStore {
        ShelfStore(root: root, now: { [unowned self] in clock }, discard: { [unowned self] url in
            discarded.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        })
    }

    func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = inbox.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.date(from: string)!
    }

    func testCapturesAreMovedAndDroppedFilesAreCopied() throws {
        let store = makeStore()
        let capture = try makeFile("Screenshot.png")
        let dropped = try makeFile("notes.pdf")

        try store.ingest(fileAt: capture, as: .screenshot, move: true)
        try store.ingest(fileAt: dropped, as: .dropped, move: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dropped.path))
        XCTAssertEqual(store.items.map(\.fileName), ["notes.pdf", "Screenshot.png"], "newest first")
        for item in store.items {
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: item).path))
        }
    }

    func testNameCollisionsGetANumber() throws {
        let store = makeStore()
        try store.ingest(fileAt: try makeFile("a.png"), as: .screenshot, move: true)
        try store.ingest(fileAt: try makeFile("a.png"), as: .screenshot, move: true)
        XCTAssertEqual(Set(store.items.map(\.fileName)), ["a.png", "a 2.png"])
    }

    func testSweepRemovesItemsADayOldButKeepsPinned() throws {
        let store = makeStore()
        clock = date("2026-11-20 02:00")
        let lateNight = try store.ingest(fileAt: try makeFile("late night.png"), as: .screenshot, move: true)
        let pinned = try store.ingest(fileAt: try makeFile("pinned.png"), as: .screenshot, move: true)
        store.setPinned(true, for: pinned.id)
        clock = date("2026-11-20 15:00")
        let afternoon = try store.ingest(fileAt: try makeFile("afternoon.png"), as: .screenshot, move: true)

        clock = date("2026-11-21 01:59")
        XCTAssertEqual(store.purgeExpired(), 0, "nothing is a day old yet")

        clock = date("2026-11-21 02:00")
        XCTAssertEqual(store.purgeExpired(), 1, "a day old exactly")
        XCTAssertEqual(discarded, [lateNight.fileName])

        clock = date("2026-11-21 15:00")
        XCTAssertEqual(store.purgeExpired(), 1)
        XCTAssertEqual(discarded, [lateNight.fileName, afternoon.fileName])
        XCTAssertEqual(store.items.map(\.id), [pinned.id], "pinned items stay however old")
    }

    func testClearKeepsPinnedUnlessAsked() throws {
        let store = makeStore()
        let a = try store.ingest(fileAt: try makeFile("a.png"), as: .screenshot, move: true)
        try store.ingest(fileAt: try makeFile("b.png"), as: .screenshot, move: true)
        store.setPinned(true, for: a.id)

        store.clear()
        XCTAssertEqual(store.items.map(\.id), [a.id])
        store.clear(includingPinned: true)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testStateSurvivesARelaunch() throws {
        var store: ShelfStore? = makeStore()
        let item = try store!.ingest(fileAt: try makeFile("a.png"), as: .simulatorScreenshot, move: true)
        store!.setPinned(true, for: item.id)
        store = nil

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.id, item.id)
        XCTAssertEqual(reloaded.items.first?.pinned, true)
        XCTAssertEqual(reloaded.items.first?.source, .simulatorScreenshot)
    }

    func testRelaunchDropsMissingFilesAndAdoptsStrayOnes() throws {
        let store = makeStore()
        let gone = try store.ingest(fileAt: try makeFile("gone.png"), as: .screenshot, move: true)
        try FileManager.default.removeItem(at: store.url(for: gone))
        try "y".write(to: store.directory.appendingPathComponent("stray.txt"), atomically: true, encoding: .utf8)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.items.map(\.fileName), ["stray.txt"])
    }

    func testReplacingContentsKeepsIdentityAndTrashesTheOriginal() throws {
        let store = makeStore()
        let item = try store.ingest(fileAt: try makeFile("shot.png"), as: .screenshot, move: true)
        let replaced = try store.replaceContents(of: item.id, with: Data("z".utf8), fileExtension: "png", suffix: "(blurred)")

        XCTAssertEqual(replaced?.id, item.id)
        XCTAssertEqual(replaced?.fileName, "shot (blurred).png")
        XCTAssertEqual(discarded, ["shot.png"])
        XCTAssertEqual(try String(contentsOf: store.url(for: replaced!), encoding: .utf8), "z")
    }

    func testAnItemDraggedBackIsRecognised() throws {
        let store = makeStore()
        let item = try store.ingest(fileAt: try makeFile("shot.png"), as: .screenshot, move: true)
        let url = store.url(for: item)

        XCTAssertEqual(store.existingItem(matching: url)?.id, item.id)
        // What a drag actually delivers: a file reference URL.
        let reference = try XCTUnwrap((url as NSURL).fileReferenceURL())
        XCTAssertEqual(store.existingItem(matching: reference)?.id, item.id)
    }

    func testAnIdenticalCopyFromElsewhereIsRecognised() throws {
        let store = makeStore()
        let item = try store.ingest(fileAt: try makeFile("shot.png", contents: "pixels"), as: .screenshot, move: true)

        XCTAssertEqual(store.existingItem(matching: try makeFile("copy on desktop.png", contents: "pixels"))?.id, item.id)
        XCTAssertNil(store.existingItem(matching: try makeFile("other.png", contents: "pixelz")), "same size, different bytes")
        XCTAssertNil(store.existingItem(matching: try makeFile("bigger.png", contents: "more pixels")))
        XCTAssertEqual(store.existingItem(matching: Data("pixels".utf8))?.id, item.id)
        XCTAssertNil(store.existingItem(matching: Data("nope".utf8)))
    }

    func testRelativeTime() {
        let now = date("2026-11-21 10:00")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-10), now: now), "now")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-4 * 60), now: now), "4m")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-2 * 86_400), now: now), "2d")
    }
}
