import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var editingApiKey = ""
    @State private var apiKeyVisible = false
    @State private var apiKeySaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Settings")
                    .font(.appLargeTitle)
                    .foregroundColor(AppColors.textPrimary)

                apiSection

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    generalSection
                    hotkeySection
                }

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    modelSection
                    dataSection
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.background)
        .onAppear {
            editingApiKey = viewModel.apiKey
        }
    }

    // MARK: - API Key Section

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("API Key")

            VStack(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    if apiKeyVisible {
                        TextField("OpenAI API Key", text: $editingApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("OpenAI API Key", text: $editingApiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { apiKeyVisible.toggle() }) {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: saveApiKey) {
                    HStack(spacing: AppSpacing.xs) {
                        if apiKeySaved {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(apiKeySaved ? "Saved" : "Save API Key")
                            .font(.appCaptionBold)
                    }
                    .foregroundColor(apiKeySaved ? AppColors.successGreen : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm + 2)
                    .background(apiKeySaved ? AppColors.successGreen.opacity(0.12) : AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(editingApiKey.isEmpty)
            }
        }
        .settingsCard()
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("General")

            Toggle("Play sound on hotkey press/release", isOn: Binding(
                get: { viewModel.soundEnabled },
                set: { viewModel.saveSoundEnabled($0) }
            ))
            .toggleStyle(.switch)
            .font(.appBody)
            .foregroundColor(AppColors.textPrimary)

            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .font(.appBody)
            .foregroundColor(AppColors.textPrimary)
        }
        .settingsCard()
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("Hotkey")

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Text("Shortcut:")
                        .font(.appBody)
                        .foregroundColor(AppColors.textSecondary)

                    Picker("", selection: Binding(
                        get: { viewModel.hotkeyModifiers },
                        set: { viewModel.saveHotkeyModifiers($0) }
                    )) {
                        ForEach(DashboardViewModel.availableHotkeys, id: \.self) { combo in
                            Text(DashboardViewModel.hotkeySymbols(combo))
                                .tag(combo)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                HStack(spacing: AppSpacing.sm) {
                    Text("Mode:")
                        .font(.appBody)
                        .foregroundColor(AppColors.textSecondary)

                    Picker("", selection: Binding(
                        get: { viewModel.recordingMode },
                        set: { viewModel.saveRecordingMode($0) }
                    )) {
                        Text("Hold").tag("hold")
                        Text("Toggle").tag("toggle")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }

                Text(viewModel.recordingMode == "hold"
                    ? "Hold keys to start dictation. Release to transcribe and paste."
                    : "Press keys once to start recording. Press again to stop and transcribe.")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .settingsCard()
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("Model")

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                settingsDetail(label: "Transcription", value: "gpt-4o-mini-transcribe")
                settingsDetail(label: "Cost", value: "$0.003 / minute")
            }
        }
        .settingsCard()
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("Data")

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                settingsDetail(label: "Profile", value: "~/.bak-bak/profile.toml")
                settingsDetail(label: "History", value: "~/.bak-bak/history.jsonl")
            }
        }
        .settingsCard()
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.appSectionTitle)
            .foregroundColor(AppColors.textSecondary)
    }

    private func settingsDetail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.appCaption)
                .foregroundColor(AppColors.textMuted)
            Text(value)
                .font(.appMonospaced)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func saveApiKey() {
        viewModel.saveApiKey(editingApiKey)
        apiKeySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
    }
}

// MARK: - Settings Card (fills column, equal height within row)

extension View {
    func settingsCard() -> some View {
        self
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.cardBorder, lineWidth: 0.5)
            )
            .shadow(color: AppShadow.card, radius: 8, y: 2)
    }
}
