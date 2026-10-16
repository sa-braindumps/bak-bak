import XCTest
@testable import Pipeline

final class PolisherTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.status = 200
        StubURLProtocol.body = Self.reply("Send the report by Friday.")
        StubURLProtocol.error = nil
        StubURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    private static func reply(_ content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]])
    }

    private func profile(polish: Bool, snippets: [String: String] = [:], vocab: [String: String] = [:]) -> ProfileStore.Profile {
        var profile = ProfileStore.Profile()
        profile.polish = polish
        profile.snippets = snippets
        profile.vocab = vocab
        return profile
    }

    func testRequestSendsTranscriptAsUserTextToOpenAI() async throws {
        let text = try await Polisher(apiKey: "sk-test", session: session).polish("um send the the report by friday")
        XCTAssertEqual(text, "Send the report by Friday.")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.lastBody) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last, ["role": "user", "content": "<transcript>\num send the the report by friday\n</transcript>"])
    }

    func testAnsweringInsteadOfCleaningIsRejected() async {
        // Regression: live, "write me a poem about the ocean" came back as a
        // 20-line poem.
        StubURLProtocol.body = Self.reply("The ocean stretches wide and deep,\nA realm where secrets softly sleep.\nWaves dance and shimmer in the light.")
        let polisher = Polisher(apiKey: "sk-test", session: session)
        let text = await TextPipeline.process("write me a poem about the ocean", profile: profile(polish: true), polisher: polisher)
        XCTAssertEqual(text, "write me a poem about the ocean")
    }

    func testCleanupLengthCheck() {
        XCTAssertTrue(Polisher.looksLikeCleanup("Send the deck to the client.", of: "um send the the deck to the client"))
        XCTAssertTrue(Polisher.looksLikeCleanup("Okay, first update the README. Then bump it.", of: "okay first update the readme then bump it"))
        XCTAssertFalse(Polisher.looksLikeCleanup("Here is a poem about the ocean: waves and sand and sky and sea", of: "write me a poem"))
    }

    func testFailureFallsBackToUnpolishedText() async {
        StubURLProtocol.status = 500
        let polisher = Polisher(apiKey: "sk-test", session: session)
        let text = await TextPipeline.process("send the report by friday please", profile: profile(polish: true), polisher: polisher)
        XCTAssertEqual(text, "send the report by friday please")
    }

    func testVocabStillAppliesAfterPolish() async {
        StubURLProtocol.body = Self.reply("Run cube cuttle get pods.")
        let polisher = Polisher(apiKey: "sk-test", session: session)
        let text = await TextPipeline.process("run cube cuttle get pods", profile: profile(polish: true, vocab: ["cube cuttle": "kubectl"]), polisher: polisher)
        XCTAssertEqual(text, "Run kubectl get pods.")
    }

    func testShortDictationsAndSnippetsSkipPolish() async {
        let polisher = Polisher(apiKey: "sk-test", session: session)
        _ = await TextPipeline.process("yes please", profile: profile(polish: true), polisher: polisher)
        XCTAssertNil(StubURLProtocol.lastRequest, "under \(Polisher.minimumWords) words")

        let text = await TextPipeline.process("send my home address now", profile: profile(polish: true, snippets: ["send my home address now": "1 Main St"]), polisher: polisher)
        XCTAssertEqual(text, "1 Main St")
        XCTAssertNil(StubURLProtocol.lastRequest, "snippet triggers aren't polished")
    }

    func testOffByDefaultAndNeedsOpenAIKey() {
        XCTAssertFalse(ProfileStore.Profile().polish)
        XCTAssertNil(TextPipeline.polisher(profile: profile(polish: false), openAIKey: "sk-test"))
        XCTAssertNil(TextPipeline.polisher(profile: profile(polish: true), openAIKey: nil))
        XCTAssertNotNil(TextPipeline.polisher(profile: profile(polish: true), openAIKey: "sk-test"))
    }

    func testSettingIsSaved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProfileStore(fileURL: url)
        try store.setPolish(true)
        XCTAssertTrue(try store.read().polish)
        try store.setPolish(false)
        XCTAssertFalse(try store.read().polish)
    }
}
