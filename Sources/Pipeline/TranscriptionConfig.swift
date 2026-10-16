import Foundation

/// Which OpenAI-compatible speech-to-text service to call, and with what.
/// Read from `[transcription]` in profile.toml; the defaults are OpenAI's
/// `gpt-4o-mini-transcribe`, which is what Bak-Bak always used.
public struct TranscriptionConfig: Codable, Equatable, Sendable {

    public static let openAIBaseURL = "https://api.openai.com/v1"
    public static let defaultModel = "gpt-4o-mini-transcribe"

    /// What the user speaks, and how it should be written.
    public enum Language: String, Codable, CaseIterable, Sendable {
        case english = "en"
        case hindi = "hi"
        /// Hindi + English mixed, written in Roman letters.
        case hinglish
        case auto

        public var label: String {
            switch self {
            case .english: return "English"
            case .hindi: return "Hindi (देवनागरी)"
            case .hinglish: return "Hinglish (Roman letters)"
            case .auto: return "Detect automatically"
            }
        }

        /// The API's `language` field. Nil lets the model detect it, which
        /// handles Hindi and English mixed in one sentence best.
        public var apiCode: String? {
            switch self {
            case .english: return "en"
            case .hindi: return "hi"
            case .hinglish, .auto: return nil
            }
        }
    }

    public var baseURL: String
    public var model: String
    /// A key just for this service. Nil means "use the OpenAI key", which is
    /// only allowed when the service *is* OpenAI.
    public var apiKey: String?
    public var language: Language

    public init(baseURL: String = openAIBaseURL, model: String = defaultModel, apiKey: String? = nil, language: Language = .english) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.language = language
    }

    public static let `default` = TranscriptionConfig()

    /// `<baseURL>/audio/transcriptions`, or nil if `baseURL` isn't a valid
    /// http(s) URL.
    public var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/audio/transcriptions"),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return url
    }

    public var host: String { endpoint?.host ?? baseURL }

    public var isOpenAI: Bool { endpoint?.host?.lowercased() == "api.openai.com" }

    /// The key to send. The OpenAI key is never sent anywhere but OpenAI.
    public func resolvedKey(openAIKey: String?) -> String? {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        guard isOpenAI, let openAIKey, !openAIKey.isEmpty else { return nil }
        return openAIKey
    }

    // MARK: - Presets

    public struct Preset: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let baseURL: String
        public let model: String
        public let note: String

        public var config: TranscriptionConfig { TranscriptionConfig(baseURL: baseURL, model: model) }
    }

    public static let presets: [Preset] = [
        Preset(id: "openai-mini", name: "OpenAI – gpt-4o-mini-transcribe",
               baseURL: openAIBaseURL, model: "gpt-4o-mini-transcribe",
               note: "Default. About $0.003 a minute."),
        Preset(id: "openai", name: "OpenAI – gpt-4o-transcribe",
               baseURL: openAIBaseURL, model: "gpt-4o-transcribe",
               note: "More accurate, about twice the price."),
        Preset(id: "groq", name: "Groq – whisper-large-v3-turbo",
               baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo",
               note: "Very fast and cheap. Needs a Groq key."),
    ]

    /// The preset this config matches, if any (the key doesn't matter).
    public var preset: Preset? {
        Self.presets.first { $0.baseURL == baseURL && $0.model == model }
    }
}

// MARK: - Building an engine from the profile

public enum TranscriptionSetupError: Error, LocalizedError, Equatable {
    case missingKey(host: String, isOpenAI: Bool)

    public var errorDescription: String? {
        switch self {
        case .missingKey(_, true):
            return "API key not set. Open Dashboard → Settings"
        case .missingKey(let host, false):
            return "No API key for \(host). Add it in Dashboard → Settings → Transcription"
        }
    }
}

extension Transcriber {
    /// The engine the profile asks for: its service, its model, the right key,
    /// and the vocabulary prompt. Used by both the app and the CLI.
    public static func make(profile: ProfileStore.Profile?, openAIKey: String?, session: URLSession = .shared) throws -> Transcriber {
        let config = profile?.transcription ?? .default
        guard let key = config.resolvedKey(openAIKey: openAIKey) else {
            throw TranscriptionSetupError.missingKey(host: config.host, isOpenAI: config.isOpenAI)
        }
        let prompt = TranscriptionPrompt.build(vocab: profile?.vocab ?? [:], order: profile?.vocabOrder ?? [], language: config.language)
        return Transcriber(apiKey: key, prompt: prompt, config: config, session: session)
    }
}
