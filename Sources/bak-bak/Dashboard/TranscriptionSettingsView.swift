import Pipeline
import SwiftUI

/// Settings card for which speech-to-text service and model to use.
/// Presets fill in the URL and model; "Custom" takes any OpenAI-compatible
/// endpoint. Services other than OpenAI need their own key, because the
/// OpenAI key is never sent anywhere else.
struct TranscriptionSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var selection = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var serviceKey = ""
    @State private var saved = false

    private static let customID = "custom"

    private var draft: TranscriptionConfig {
        TranscriptionConfig(baseURL: baseURL, model: model, apiKey: serviceKey.isEmpty ? nil : serviceKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Transcription")
                .font(.appSectionTitle)
                .foregroundColor(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Picker("", selection: $selection) {
                    ForEach(TranscriptionConfig.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Text("Custom (OpenAI-compatible)").tag(Self.customID)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: selection, perform: applyPreset)

                if let note = TranscriptionConfig.presets.first(where: { $0.id == selection })?.note {
                    Text(note)
                        .font(.appCaption)
                        .foregroundColor(AppColors.textMuted)
                }

                if selection == Self.customID {
                    TextField("Base URL, e.g. https://api.groq.com/openai/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                if !draft.isOpenAI {
                    SecureField("API key for \(draft.host)", text: $serviceKey)
                        .textFieldStyle(.roundedBorder)
                }

                if draft.endpoint == nil {
                    Text("That URL doesn't look right. It should start with https://")
                        .font(.appCaption)
                        .foregroundColor(AppColors.warningAmber)
                }

                Button(action: save) {
                    Text(saved ? "Saved" : "Save")
                        .font(.appCaptionBold)
                        .foregroundColor(saved ? AppColors.successGreen : AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(saved ? AppColors.successGreen.opacity(0.12) : AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private var canSave: Bool {
        draft.endpoint != nil && !model.isEmpty && (draft.isOpenAI || !serviceKey.isEmpty)
    }

    private func load() {
        let config = viewModel.transcription
        baseURL = config.baseURL
        model = config.model
        serviceKey = config.apiKey ?? ""
        selection = config.preset?.id ?? Self.customID
    }

    private func applyPreset(_ id: String) {
        guard let preset = TranscriptionConfig.presets.first(where: { $0.id == id }) else { return }
        if preset.baseURL != baseURL { serviceKey = "" }
        baseURL = preset.baseURL
        model = preset.model
    }

    private func save() {
        viewModel.saveTranscription(draft)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
