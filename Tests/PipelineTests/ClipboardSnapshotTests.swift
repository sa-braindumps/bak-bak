import AppKit
import XCTest
@testable import Pipeline

final class ClipboardSnapshotTests: XCTestCase {

    var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("bak-bak-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testRestoresEveryTypeOfEveryItem() {
        // Regression: only the first type of each item came back, so rich
        // text lost its formatting.
        let rich = NSPasteboardItem()
        rich.setString("hello", forType: .string)
        rich.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf)
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        pasteboard.writeObjects([rich, second])

        let snapshot = ClipboardSnapshot(of: pasteboard)
        let count = ClipboardSnapshot.placeTransient("dictated text", on: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")

        XCTAssertTrue(snapshot.restore(to: pasteboard, ifUnchangedSince: count))
        let items = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.string(forType: .string), "hello")
        XCTAssertEqual(items.first?.data(forType: .rtf), Data("{\\rtf1 hello}".utf8))
        XCTAssertEqual(items.last?.string(forType: .URL), "https://example.com")
    }

    func testDictationIsMarkedTransient() {
        ClipboardSnapshot.placeTransient("dictated text", on: pasteboard)
        let types = pasteboard.pasteboardItems?.first?.types ?? []
        XCTAssertTrue(types.contains(ClipboardSnapshot.transientType))
    }

    func testDoesNotClobberSomethingCopiedAfterThePaste() {
        pasteboard.setString("old", forType: .string)
        let snapshot = ClipboardSnapshot(of: pasteboard)
        let count = ClipboardSnapshot.placeTransient("dictated text", on: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("user copied this", forType: .string)

        XCTAssertFalse(snapshot.restore(to: pasteboard, ifUnchangedSince: count))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied this")
    }

    func testEmptyClipboardStaysEmpty() {
        let snapshot = ClipboardSnapshot(of: pasteboard)
        XCTAssertTrue(snapshot.isEmpty)
        let count = ClipboardSnapshot.placeTransient("dictated text", on: pasteboard)
        snapshot.restore(to: pasteboard, ifUnchangedSince: count)
        XCTAssertNil(pasteboard.string(forType: .string), "dictation shouldn't linger on the clipboard")
    }
}
