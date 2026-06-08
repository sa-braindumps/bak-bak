import XCTest
@testable import Pipeline

final class SubstitutorTests: XCTestCase {

    func testEmptyVocabReturnsUnchanged() {
        let input = "run cube cuttle get pods"
        let result = Substitutor.apply(input, vocab: [:])
        XCTAssertEqual(result, input)
    }

    func testBasicReplacement() {
        let vocab = ["cube cuttle": "kubectl"]
        let result = Substitutor.apply("run cube cuttle get pods", vocab: vocab)
        XCTAssertEqual(result, "run kubectl get pods")
    }

    func testCaseInsensitiveMatching() {
        let vocab = ["nicks": "Nginx"]
        let result1 = Substitutor.apply("deploy nicks server", vocab: vocab)
        let result2 = Substitutor.apply("deploy NICKS server", vocab: vocab)
        let result3 = Substitutor.apply("deploy Nicks server", vocab: vocab)
        XCTAssertEqual(result1, "deploy Nginx server")
        XCTAssertEqual(result2, "deploy Nginx server")
        XCTAssertEqual(result3, "deploy Nginx server")
    }

    func testPreservesReplacementCase() {
        let vocab = ["rack bak": "Bak-Bak"]
        let result = Substitutor.apply("use rack bak for dictation", vocab: vocab)
        XCTAssertEqual(result, "use Bak-Bak for dictation")
    }

    func testTokenBoundaryNoPartialMatch() {
        let vocab = ["nicks": "Nginx"]
        // "nicks" should not match inside "picnicks"
        let result = Substitutor.apply("picnicks server", vocab: vocab)
        XCTAssertEqual(result, "picnicks server")
    }

    func testTokenBoundaryStartOfWord() {
        let vocab = ["nicks": "Nginx"]
        let result = Substitutor.apply("nicks is fast", vocab: vocab)
        XCTAssertEqual(result, "Nginx is fast")
    }

    func testLongestKeyWins() {
        let vocab = [
            "cube": "K8s",
            "cube cuttle": "kubectl"
        ]
        let result = Substitutor.apply("run cube cuttle get pods", vocab: vocab)
        XCTAssertEqual(result, "run kubectl get pods")
    }

    func testMultipleSubstitutions() {
        let vocab = [
            "cube cuttle": "kubectl",
            "nicks": "Nginx"
        ]
        let result = Substitutor.apply("run cube cuttle with nicks", vocab: vocab)
        XCTAssertEqual(result, "run kubectl with Nginx")
    }

    func testNoMatchPassesThrough() {
        let vocab = ["cube cuttle": "kubectl"]
        let result = Substitutor.apply("hello world", vocab: vocab)
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyInput() {
        let vocab = ["cube cuttle": "kubectl"]
        let result = Substitutor.apply("", vocab: vocab)
        XCTAssertEqual(result, "")
    }

    func testSingleWordVocabEntry() {
        let vocab = ["kubectl": "kubectl"]
        let result = Substitutor.apply("run kubectl get pods", vocab: vocab)
        XCTAssertEqual(result, "run kubectl get pods")
    }
}
