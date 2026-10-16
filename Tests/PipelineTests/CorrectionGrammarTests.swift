import XCTest
@testable import Pipeline

final class CorrectionGrammarTests: XCTestCase {

    // MARK: - Pattern: "no, X is Y"

    func testNoPatternBasic() {
        let result = CorrectionGrammar.parse("no, cube cuttle is kubectl")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    func testNoPatternCaseInsensitive() {
        let result = CorrectionGrammar.parse("No, nicks is Nginx")
        XCTAssertEqual(result?.heard, "nicks")
        XCTAssertEqual(result?.intended, "Nginx")
    }

    func testNoPatternWithExtraSpaces() {
        let result = CorrectionGrammar.parse("no,  cube cuttle  is  kubectl  ")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    // MARK: - Pattern: "correction: X is Y"

    func testCorrectionPatternBasic() {
        let result = CorrectionGrammar.parse("correction: cube cuttle is kubectl")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    func testCorrectionPatternWithoutColon() {
        let result = CorrectionGrammar.parse("correction cube cuttle is kubectl")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    func testCorrectionPatternCaseInsensitive() {
        let result = CorrectionGrammar.parse("CORRECTION: nicks is Nginx")
        XCTAssertEqual(result?.heard, "nicks")
        XCTAssertEqual(result?.intended, "Nginx")
    }

    // MARK: - Pattern: "actually X is Y"

    func testActuallyPatternBasic() {
        let result = CorrectionGrammar.parse("actually nicks is Nginx")
        XCTAssertEqual(result?.heard, "nicks")
        XCTAssertEqual(result?.intended, "Nginx")
    }

    func testActuallyPatternCaseInsensitive() {
        let result = CorrectionGrammar.parse("Actually cube cuttle is kubectl")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    // MARK: - Non-matching utterances

    func testPlainDictationReturnsNil() {
        let result = CorrectionGrammar.parse("run kubectl get pods")
        XCTAssertNil(result)
    }

    func testEmptyStringReturnsNil() {
        let result = CorrectionGrammar.parse("")
        XCTAssertNil(result)
    }

    func testOnlyKeywordReturnsNil() {
        let result = CorrectionGrammar.parse("no")
        XCTAssertNil(result)
    }

    func testKeywordWithoutConnectiveReturnsNil() {
        let result = CorrectionGrammar.parse("no cube cuttle")
        XCTAssertNil(result)
    }

    func testConnectiveWithoutKeywordReturnsNil() {
        let result = CorrectionGrammar.parse("cube cuttle is kubectl")
        XCTAssertNil(result)
    }

    // MARK: - Edge cases

    func testMultiWordHeard() {
        let result = CorrectionGrammar.parse("no, the cube cuttle command is kubectl")
        XCTAssertEqual(result?.heard, "the cube cuttle command")
        XCTAssertEqual(result?.intended, "kubectl")
    }

    func testMultiWordIntended() {
        let result = CorrectionGrammar.parse("no, nicks is Nginx web server")
        XCTAssertEqual(result?.heard, "nicks")
        XCTAssertEqual(result?.intended, "Nginx web server")
    }

    func testPunctuationStripping() {
        let result = CorrectionGrammar.parse("no, rack bak is Bak-Bak.")
        XCTAssertEqual(result?.heard, "rack bak")
        XCTAssertEqual(result?.intended, "Bak-Bak")
    }

    // MARK: - Must look like a word fix

    func testEverydaySentenceIsNotACorrection() {
        // Regression: this used to save "the meeting" → "at 3pm." to vocab.
        XCTAssertNil(CorrectionGrammar.parse("Actually the meeting is at 3pm.", lastText: "Send the invite for Friday."))
    }

    func testHeardMustAppearInLastText() {
        let last = "run cube cuttle get pods"
        XCTAssertNotNil(CorrectionGrammar.parse("No, cube cuttle is kubectl.", lastText: last))
        XCTAssertNil(CorrectionGrammar.parse("No, nicks is Nginx.", lastText: last))
    }

    func testHeardMatchesWholeWordsOnly() {
        XCTAssertNil(CorrectionGrammar.parse("no, nick is Nginx", lastText: "ask the nickname"))
        XCTAssertNotNil(CorrectionGrammar.parse("no, Nick is Nginx", lastText: "restart nick, then reload"))
    }

    func testLongSidesAreNotACorrection() {
        XCTAssertNil(CorrectionGrammar.parse("no, the plan we agreed on yesterday is wrong"))
        XCTAssertNil(CorrectionGrammar.parse("actually nicks is the thing we use for routing traffic"))
    }

    func testLonePronounIsNotACorrection() {
        XCTAssertNil(CorrectionGrammar.parse("No, that is fine.", lastText: "is that fine"))
        XCTAssertNil(CorrectionGrammar.parse("actually it is broken", lastText: "it works"))
    }

    func testSameOnBothSidesIsNotACorrection() {
        XCTAssertNil(CorrectionGrammar.parse("no, kubectl is Kubectl", lastText: "kubectl get pods"))
    }

    func testDotInsideWordIsKept() {
        XCTAssertEqual(CorrectionGrammar.parse("no, node js is Node.js")?.intended, "Node.js")
    }

    func testQuotesAreStripped() {
        let result = CorrectionGrammar.parse("no, \"cube cuttle\" is \"kubectl\".")
        XCTAssertEqual(result?.heard, "cube cuttle")
        XCTAssertEqual(result?.intended, "kubectl")
    }
}
