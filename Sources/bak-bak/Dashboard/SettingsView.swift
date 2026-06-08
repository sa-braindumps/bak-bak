import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var editingApiKey = ""
    @State private var apiKeyVisible = false
    @State private var apiKeySaved = false

    var body: some View {
        Form {
            Section("API Key") {
                HStack {
                    if apiKeyVisible {
                        TextField("OpenAI API Key", text: $editingApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("OpenAI API Key", text: $editingApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { apiKeyVisible.toggle() }) {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                Button(apiKeySaved ? "Saved" : "Save API Key") {
                    viewModel.saveApiKey(editingApiKey)
                    apiKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                }
                .disabled(editingApiKey.isEmpty)
            }

            Section("Sound") {
                Toggle("Play sound on hotkey press/release", isOn: Binding(
                    get: { viewModel.soundEnabled },
                    set: { viewModel.saveSoundEnabled($0) }
                ))
            }

            Section("Hotkey") {
                HStack {
                    Text("Hold to record:")
                    Text("Control + Option (\u{2303}\u{2325})")
                        .fontWeight(.medium)
                }
                Text("Press and hold both keys to start dictation. Release to transcribe and paste.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Model") {
                HStack {
                    Text("Transcription:")
                    Text("gpt-4o-mini-transcribe")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Cost:")
                    Text("$0.003 / minute")
                        .foregroundColor(.secondary)
                }
            }

            Section("Data") {
                HStack {
                    Text("Profile:")
                    Text("~/.bak-bak/profile.toml")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("History:")
                    Text("~/.bak-bak/history.jsonl")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            editingApiKey = viewModel.apiKey
        }
    }
}
