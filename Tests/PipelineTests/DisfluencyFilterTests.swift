import XCTest
@testable import Pipeline

final class DisfluencyFilterTests: XCTestCase {

    // MARK: - Whole-token removal

    func testRemovesFillersAsWholeTokens() {
        XCTAssertEqual(DisfluencyFilter.apply("um I think uh we should go"), "I think we should go")
    }

    func testRemovesVariants() {
        XCTAssertEqual(DisfluencyFilter.apply("umm yeah erm okay hmm sure"), "Yeah okay sure")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(DisfluencyFilter.apply("Um okay Uh sure"), "Okay sure")
    }

    // MARK: - Real words preserved

    func testKeepsLike() {
        XCTAssertEqual(DisfluencyFilter.apply("it was like really good"), "it was like really good")
    }

    func testKeepsSoAndYouKnow() {
        let input = "so you know it works"
        XCTAssertEqual(DisfluencyFilter.apply(input), input)
    }

    // MARK: - Does not gut substrings

    func testDoesNotGutSummary() {
        XCTAssertEqual(DisfluencyFilter.apply("write the summary now"), "write the summary now")
    }

    func testDoesNotTouchAhem() {
        XCTAssertEqual(DisfluencyFilter.apply("ahem excuse me"), "ahem excuse me")
    }

    // MARK: - Spacing + punctuation cleanup

    func testCollapsesDoubleSpaces() {
        XCTAssertEqual(DisfluencyFilter.apply("hello um world"), "hello world")
    }

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(DisfluencyFilter.apply("I think um , then we go"), "I think, then we go")
    }

    // MARK: - Re-capitalization

    func testRecapitalizesAfterLeadingFiller() {
        XCTAssertEqual(DisfluencyFilter.apply("um the meeting is at noon"), "The meeting is at noon")
    }

    func testDoesNotRecapitalizeWhenNoLeadingFiller() {
        // Already starts clean and lowercase — must be left as-is.
        XCTAssertEqual(DisfluencyFilter.apply("run kubectl get pods"), "run kubectl get pods")
    }

    // MARK: - Passthrough

    func testNoFillersPassthrough() {
        let input = "The quick brown fox"
        XCTAssertEqual(DisfluencyFilter.apply(input), input)
    }

    func testEmptyInput() {
        XCTAssertEqual(DisfluencyFilter.apply(""), "")
    }
}
