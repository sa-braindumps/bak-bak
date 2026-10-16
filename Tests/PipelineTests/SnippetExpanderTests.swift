import XCTest
@testable import Pipeline

final class SnippetExpanderTests: XCTestCase {

    private let snippets = [
        "my address": "123 Main St\nSpringfield",
        "sign off": "Best regards,\nShivam",
        "my email": "shivam@example.com",
    ]

    // MARK: - Whole-utterance match

    func testWholeUtteranceMatch() {
        let result = SnippetExpander.apply("my email", snippets: snippets)
        XCTAssertEqual(result, "shivam@example.com")
    }

    func testCaseInsensitiveMatch() {
        XCTAssertEqual(SnippetExpander.apply("My Email", snippets: snippets), "shivam@example.com")
        XCTAssertEqual(SnippetExpander.apply("MY EMAIL", snippets: snippets), "shivam@example.com")
    }

    func testTrailingPunctuationTolerated() {
        XCTAssertEqual(SnippetExpander.apply("my email.", snippets: snippets), "shivam@example.com")
        XCTAssertEqual(SnippetExpander.apply("my email!", snippets: snippets), "shivam@example.com")
        XCTAssertEqual(SnippetExpander.apply("  my email  ", snippets: snippets), "shivam@example.com")
    }

    // MARK: - No embedded / mid-sentence expansion

    func testNoEmbeddedMatch() {
        // The trigger appears mid-sentence — must NOT expand in v1.
        let input = "please send my email to the team"
        XCTAssertEqual(SnippetExpander.apply(input, snippets: snippets), input)
    }

    func testPartialUtteranceNoMatch() {
        let input = "my email address"
        XCTAssertEqual(SnippetExpander.apply(input, snippets: snippets), input)
    }

    // MARK: - Longest trigger wins

    func testLongestTriggerWins() {
        let overlapping = [
            "send": "SHORT",
            "send my address": "123 Main St",
        ]
        XCTAssertEqual(SnippetExpander.apply("send my address", snippets: overlapping), "123 Main St")
    }

    // MARK: - Passthrough

    func testEmptySnippetsPassthrough() {
        XCTAssertEqual(SnippetExpander.apply("my email", snippets: [:]), "my email")
    }

    func testNonMatchingPassthrough() {
        XCTAssertEqual(SnippetExpander.apply("hello world", snippets: snippets), "hello world")
    }

    func testEmptyInputPassthrough() {
        XCTAssertEqual(SnippetExpander.apply("", snippets: snippets), "")
    }

    // MARK: - Multi-line expansion preserved

    func testMultiLineExpansionPreserved() {
        let result = SnippetExpander.apply("my address", snippets: snippets)
        XCTAssertEqual(result, "123 Main St\nSpringfield")
        XCTAssertTrue(result.contains("\n"))
    }
}
