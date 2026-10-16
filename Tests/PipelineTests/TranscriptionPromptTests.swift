import XCTest
@testable import Pipeline

final class TranscriptionPromptTests: XCTestCase {

    func testNoVocabKeepsTheOldPrompt() {
        XCTAssertEqual(TranscriptionPrompt.build(vocab: [:]), "Voice dictation.")
    }

    func testListsIntendedTermsNewestFirst() {
        let vocab = ["cube cuttle": "kubectl", "nicks": "Nginx", "rack bak": "Bak-Bak"]
        let prompt = TranscriptionPrompt.build(vocab: vocab, order: ["cube cuttle", "nicks", "rack bak"])
        XCTAssertEqual(prompt, "Voice dictation. Vocabulary: Bak-Bak, Nginx, kubectl.")
    }

    func testSendsTheFixNotTheMishearing() {
        let prompt = TranscriptionPrompt.build(vocab: ["cube cuttle": "kubectl"], order: ["cube cuttle"])
        XCTAssertFalse(prompt.contains("cube cuttle"))
        XCTAssertTrue(prompt.contains("kubectl"))
    }

    func testDuplicateTermsAppearOnce() {
        let vocab = ["cube cuttle": "kubectl", "cube control": "kubectl", "kube ctl": "Kubectl"]
        let prompt = TranscriptionPrompt.build(vocab: vocab, order: ["cube cuttle", "cube control", "kube ctl"])
        XCTAssertEqual(prompt, "Voice dictation. Vocabulary: Kubectl.")
    }

    func testCapKeepsTheNewestTerms() {
        var vocab: [String: String] = [:]
        var order: [String] = []
        for i in 0..<300 {
            vocab["heard \(i)"] = "term\(i)"
            order.append("heard \(i)")
        }
        let prompt = TranscriptionPrompt.build(vocab: vocab, order: order)
        let listed = prompt.dropFirst("Voice dictation. Vocabulary: ".count).dropLast().components(separatedBy: ", ")
        XCTAssertEqual(listed.count, TranscriptionPrompt.maxWords)
        XCTAssertEqual(listed.first, "term299")
        XCTAssertFalse(prompt.contains("term0,"))
    }

    func testKeysMissingFromOrderStillCount() {
        let prompt = TranscriptionPrompt.build(vocab: ["nicks": "Nginx"], order: [])
        XCTAssertEqual(prompt, "Voice dictation. Vocabulary: Nginx.")
    }

    func testProfileReadKeepsFileOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProfileStore(fileURL: url)
        try store.addVocabEntry(heard: "zeta", intended: "Z")
        try store.addVocabEntry(heard: "alpha", intended: "A")
        XCTAssertEqual(try store.read().vocabOrder, ["zeta", "alpha"])
    }
}
