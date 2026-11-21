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

    func testDayStartsAtFourInTheMorning() {
        XCTAssertEqual(ShelfStore.dayStart(containing: date("2026-11-21 10:00")), date("2026-11-21 04:00"))
        XCTAssertEqual(ShelfStore.dayStart(containing: date("2026-11-21 01:30")), date("2026-11-20 04:00"))
        XCTAssertEqual(ShelfStore.dayStart(containing: date("2026-11-21 04:00")), date("2026-11-21 04:00"))
    }

    func testSweepRemovesYesterdayButKeepsPinnedAndToday() throws {
        let store = makeStore()
        clock = date("2026-11-20 15:00")
        let old = try store.ingest(fileAt: try makeFile("old.png"), as: .screenshot, move: true)
        let pinned = try store.ingest(fileAt: try makeFile("pinned.png"), as: .screenshot, move: true)
        store.setPinned(true, for: pinned.id)
        clock = date("2026-11-20 23:58")
        let late = try store.ingest(fileAt: try makeFile("late.png"), as: .screenshot, move: true)

        clock = date("2026-11-21 00:30")
        XCTAssertEqual(store.purgeExpired(), 0, "nothing goes before 4 AM")

        clock = date("2026-11-21 09:00")
        XCTAssertEqual(store.purgeExpired(), 2)
        XCTAssertEqual(store.items.map(\.id), [pinned.id])
        XCTAssertEqual(Set(discarded), [old.fileName, late.fileName])
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

    func testRelativeTime() {
        let now = date("2026-11-21 10:00")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-10), now: now), "now")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-4 * 60), now: now), "4m")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-2 * 86_400), now: now), "2d")
    }
}
