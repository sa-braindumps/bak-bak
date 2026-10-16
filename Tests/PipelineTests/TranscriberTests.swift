import XCTest
@testable import Pipeline

/// Intercepts every request made through a session that uses it, records it,
/// and answers with a canned status and body.
final class StubURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data(#"{"text":"hello"}"#.utf8)
    static var error: URLError?
    static var lastRequest: URLRequest?
    static var lastBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class TranscriberTests: XCTestCase {

    private var session: URLSession!
    private let audio = Data(count: 16_000 * MemoryLayout<Float>.size)  // 1s of silence

    override func setUp() {
        super.setUp()
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"text":"hello"}"#.utf8)
        StubURLProtocol.error = nil
        StubURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    private func transcribe(_ config: TranscriptionConfig = .default, key: String = "sk-test", prompt: String = "Voice dictation.") async throws -> String {
        try await Transcriber(apiKey: key, prompt: prompt, config: config, session: session).transcribe(audioData: audio).text
    }

    private func assertThrows(_ expected: Transcriber.TranscriptionError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await transcribe()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? Transcriber.TranscriptionError, expected, file: file, line: line)
        }
    }

    // MARK: - Request

    func testDefaultRequestGoesToOpenAIWithTheSameFieldsAsBefore() async throws {
        let text = try await transcribe()
        XCTAssertEqual(text, "hello")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = String(decoding: StubURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nVoice dictation.\r\n"))
    }

    func testCustomServiceUsesItsURLModelAndKey() async throws {
        let groq = TranscriptionConfig(baseURL: "https://api.groq.com/openai/v1/", model: "whisper-large-v3-turbo")
        _ = try await transcribe(groq, key: "gsk-test", prompt: "Voice dictation. Vocabulary: Zentrafy.")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk-test")
        let body = String(decoding: StubURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(body.contains("Vocabulary: Zentrafy."))
    }

    func testInvalidURLFailsBeforeSendingAnything() async {
        do {
            _ = try await transcribe(TranscriptionConfig(baseURL: "not a url"))
            XCTFail("expected invalidEndpoint")
        } catch {
            XCTAssertEqual(error as? Transcriber.TranscriptionError, .invalidEndpoint("not a url"))
        }
        XCTAssertNil(StubURLProtocol.lastRequest)
    }

    // MARK: - Errors (regression: 400/403/413 used to say "no network",
    // every non-offline URLError said "timed out")

    func testStatusCodesMapToHonestErrors() async {
        StubURLProtocol.status = 401
        await assertThrows(.apiKeyRejected(host: "api.openai.com"))
        StubURLProtocol.status = 403
        await assertThrows(.apiKeyRejected(host: "api.openai.com"))
        StubURLProtocol.status = 429
        await assertThrows(.rateLimited)
        StubURLProtocol.status = 503
        await assertThrows(.serverError(503))
    }

    func testBadRequestShowsTheServiceMessage() async {
        StubURLProtocol.status = 400
        StubURLProtocol.body = Data(#"{"error":{"message":"Audio file is too short."}}"#.utf8)
        await assertThrows(.badRequest("Audio file is too short."))

        StubURLProtocol.status = 413
        StubURLProtocol.body = Data()
        await assertThrows(.badRequest("HTTP 413"))

        StubURLProtocol.status = 404
        StubURLProtocol.body = Data(#"{"error":{"message":"The model `nope` does not exist"}}"#.utf8)
        await assertThrows(.modelNotFound("The model `nope` does not exist"))
    }

    func testURLErrorsMapToHonestErrors() async {
        StubURLProtocol.error = URLError(.timedOut)
        await assertThrows(.timeout)
        StubURLProtocol.error = URLError(.notConnectedToInternet)
        await assertThrows(.noNetwork)
        StubURLProtocol.error = URLError(.cannotFindHost)
        await assertThrows(.noNetwork)
    }

    func testEmptyResponseHasAMessage() async {
        StubURLProtocol.body = Data("{}".utf8)
        await assertThrows(.emptyResponse)
        XCTAssertNotNil(Transcriber.TranscriptionError.emptyResponse.errorDescription)
    }

    // MARK: - Config and keys

    func testOpenAIKeyIsNeverSentToAnotherService() {
        let groq = TranscriptionConfig(baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo")
        XCTAssertNil(groq.resolvedKey(openAIKey: "sk-openai"))
        XCTAssertThrowsError(try Transcriber.make(profile: profile(with: groq), openAIKey: "sk-openai")) { error in
            XCTAssertEqual(error as? TranscriptionSetupError, .missingKey(host: "api.groq.com", isOpenAI: false))
        }
    }

    func testServiceKeyWinsAndOpenAIFallsBackToTheMainKey() {
        var groq = TranscriptionConfig(baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo")
        groq.apiKey = "gsk-own"
        XCTAssertEqual(groq.resolvedKey(openAIKey: "sk-openai"), "gsk-own")
        XCTAssertEqual(TranscriptionConfig.default.resolvedKey(openAIKey: "sk-openai"), "sk-openai")
        XCTAssertNil(TranscriptionConfig.default.resolvedKey(openAIKey: ""))
    }

    func testPresetsAreRecognised() {
        XCTAssertEqual(TranscriptionConfig.default.preset?.id, "openai-mini")
        XCTAssertEqual(TranscriptionConfig.presets.first { $0.id == "groq" }?.config.isOpenAI, false)
        XCTAssertNil(TranscriptionConfig(baseURL: "http://localhost:8000/v1", model: "x").preset)
    }

    func testProfileReadsAndWritesTranscriptionSection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProfileStore(fileURL: url)
        XCTAssertEqual(try store.read().transcription, .default)

        try store.setTranscription(TranscriptionConfig(baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo", apiKey: "gsk-1"))
        XCTAssertEqual(try store.read().transcription.apiKey, "gsk-1")

        try store.setTranscription(.default)
        let config = try store.read().transcription
        XCTAssertEqual(config, .default)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("gsk-1"), "switching back removes the other service's key")
    }

    private func profile(with config: TranscriptionConfig) -> ProfileStore.Profile {
        var profile = ProfileStore.Profile()
        profile.transcription = config
        return profile
    }

    // MARK: - Language

    func testLanguageField() async throws {
        func body(_ language: TranscriptionConfig.Language) async throws -> String {
            _ = try await transcribe(TranscriptionConfig(language: language))
            return String(decoding: StubURLProtocol.lastBody, as: UTF8.self)
        }
        let english = try await body(.english)
        XCTAssertTrue(english.contains("name=\"language\"\r\n\r\nen\r\n"))
        let hindi = try await body(.hindi)
        XCTAssertTrue(hindi.contains("name=\"language\"\r\n\r\nhi\r\n"))
        let hinglish = try await body(.hinglish)
        XCTAssertFalse(hinglish.contains("name=\"language\""), "Hinglish lets the model detect the language")
        let auto = try await body(.auto)
        XCTAssertFalse(auto.contains("name=\"language\""))
    }

    func testLanguageIsSavedAndUnknownValuesFallBackToEnglish() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProfileStore(fileURL: url)
        try store.setTranscription(TranscriptionConfig(language: .hinglish))
        XCTAssertEqual(try store.read().transcription.language, .hinglish)

        try "[transcription]\nlanguage = \"klingon\"\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.read().transcription.language, .english)
    }

    func testHinglishPipelineRomanizesBeforeVocab() {
        var profile = ProfileStore.Profile()
        profile.transcription.language = .hinglish
        profile.vocab = ["vala": "wala"]
        XCTAssertEqual(TextPipeline.process("कल मीटिंग वाला इश्यू", profile: profile), "kal meeting wala issue")

        profile.transcription.language = .hindi
        XCTAssertEqual(TextPipeline.process("कल मीटिंग", profile: profile), "कल मीटिंग", "Hindi mode keeps Devanagari")
    }

    func testHinglishPromptUsesExampleSpeech() {
        XCTAssertEqual(TranscriptionPrompt.build(vocab: [:], language: .hinglish), TranscriptionPrompt.hinglishBase)
        XCTAssertTrue(TranscriptionPrompt.build(vocab: ["x": "Zentrafy"], language: .hinglish).hasSuffix("Vocabulary: Zentrafy."))
        XCTAssertEqual(TranscriptionPrompt.build(vocab: [:], language: .hindi), "Voice dictation.")
    }
}
