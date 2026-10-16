import ArgumentParser
import Foundation
import Pipeline

/// `bak-bak transcribe <file>`: run an audio file through the same steps as a
/// dictation (service + vocab prompt → transcription → fillers, vocab,
/// snippets) and print the result instead of typing it. For checking a
/// service, a model or a vocabulary change without touching the keyboard.
struct Transcribe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file the way a dictation would be, and print the text."
    )

    @Argument(help: "Audio file (wav, aiff, m4a, mp3, flac…)")
    var file: String

    @Flag(name: .long, help: "Also print the raw transcript, prompt and service.")
    var verbose = false

    @Option(name: .long, help: "Use this profile.toml instead of ~/.bak-bak/profile.toml.")
    var profile: String?

    func run() throws {
        // The CLI root is synchronous (main.swift also starts the app), so
        // block on the async work here.
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Void, Error> = .success(())
        Task {
            do { try await transcribeFile() } catch { outcome = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        try outcome.get()
    }

    private func transcribeFile() async throws {
        let store = ProfileStore(fileURL: self.profile.map { URL(fileURLWithPath: $0) })
        let profile = try? store.read()
        let config = profile?.transcription ?? .default

        let audio = try AudioFileLoader.loadPCM(from: URL(fileURLWithPath: file))
        let transcriber = try Transcriber.make(profile: profile, openAIKey: try? store.getApiKey())
        let result = try await transcriber.transcribe(audioData: audio)
        let polisher = TextPipeline.polisher(profile: profile, openAIKey: try? store.getApiKey())
        let text = await TextPipeline.process(result.text, profile: profile, polisher: polisher)

        if verbose {
            let prompt = TranscriptionPrompt.build(vocab: profile?.vocab ?? [:], order: profile?.vocabOrder ?? [], language: config.language)
            print("service: \(config.host)  model: \(config.model)  language: \(config.language.rawValue)  latency: \(result.latencyMs) ms")
            print("prompt:  \(prompt)")
            print("raw:     \(result.text)")
            print("final:   \(text)")
        } else {
            print(text)
        }
    }
}
