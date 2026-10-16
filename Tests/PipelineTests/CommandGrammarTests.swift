import XCTest
@testable import Pipeline

final class CommandGrammarTests: XCTestCase {

    // MARK: - scratch that

    func testScratchThat() {
        XCTAssertEqual(CommandGrammar.parse("scratch that"), .scratchThat)
    }

    func testDeleteThat() {
        XCTAssertEqual(CommandGrammar.parse("delete that"), .scratchThat)
    }

    func testUndoThat() {
        XCTAssertEqual(CommandGrammar.parse("undo that"), .scratchThat)
    }

    // MARK: - new line / new paragraph

    func testNewLine() {
        XCTAssertEqual(CommandGrammar.parse("new line"), .newLine(1))
    }

    func testNewParagraph() {
        XCTAssertEqual(CommandGrammar.parse("new paragraph"), .newLine(2))
    }

    // MARK: - select

    func testSelectThat() {
        XCTAssertEqual(CommandGrammar.parse("select that"), .selectLast)
    }

    func testSelectLastSentence() {
        XCTAssertEqual(CommandGrammar.parse("select last sentence"), .selectLast)
    }

    // MARK: - Case insensitivity + trailing punctuation

    func testCaseInsensitive() {
        XCTAssertEqual(CommandGrammar.parse("Scratch That"), .scratchThat)
        XCTAssertEqual(CommandGrammar.parse("NEW PARAGRAPH"), .newLine(2))
    }

    func testTrailingPunctuationTolerated() {
        XCTAssertEqual(CommandGrammar.parse("scratch that."), .scratchThat)
        XCTAssertEqual(CommandGrammar.parse("new line!"), .newLine(1))
        XCTAssertEqual(CommandGrammar.parse("  select that  "), .selectLast)
    }

    // MARK: - Non-commands

    func testPlainDictationReturnsNil() {
        XCTAssertNil(CommandGrammar.parse("run kubectl get pods"))
    }

    func testEmbeddedPhraseReturnsNil() {
        // Must be a whole-utterance command, not embedded.
        XCTAssertNil(CommandGrammar.parse("please scratch that itch"))
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(CommandGrammar.parse(""))
    }

    func testMakeThatMoreFormalIsNotACommand() {
        // Phase 2 LLM feature — must NOT be parsed as a v1 command.
        XCTAssertNil(CommandGrammar.parse("make that more formal"))
    }
}
