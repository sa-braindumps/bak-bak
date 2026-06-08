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
        XCTAssertEqual(result?.intended, "Bak-Bak.")
    }
}
