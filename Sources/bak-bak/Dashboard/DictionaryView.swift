import SwiftUI

struct DictionaryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var newHeard = ""
    @State private var newIntended = ""
    @State private var searchText = ""

    private var filteredVocab: [(key: String, value: String)] {
        let sorted = viewModel.vocab.sorted(by: { $0.key < $1.key })
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            addEntryRow
            Rectangle().fill(AppColors.divider).frame(height: 1)
            searchBar
            Rectangle().fill(AppColors.divider).frame(height: 1)

            if viewModel.vocab.isEmpty {
                emptyState
            } else if filteredVocab.isEmpty {
                noResults
            } else {
                vocabList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Dictionary")
                .font(.appLargeTitle)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            if viewModel.vocab.count > 0 {
                Text("\(viewModel.vocab.count) entries")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - Add Entry Row

    private var addEntryRow: some View {
        HStack(spacing: AppSpacing.sm) {
            TextField("What Whisper hears", text: $newHeard)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accent)
            TextField("What you mean", text: $newIntended)
                .textFieldStyle(.roundedBorder)

            Button(action: addEntry) {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(newHeard.isEmpty || newIntended.isEmpty
                          ? AppColors.textMuted.opacity(0.12)
                          : AppColors.accent)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(newHeard.isEmpty || newIntended.isEmpty ? AppColors.textMuted : .white)
                    )
            }
            .buttonStyle(.plain)
            .disabled(newHeard.isEmpty || newIntended.isEmpty)
            .help("Add vocabulary entry")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textMuted)
            TextField("Search vocabulary...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.appBody)
                .foregroundColor(AppColors.textPrimary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + 2)
        .background(AppColors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(searchText.isEmpty ? AppColors.inputBorder : AppColors.inputBorderFocus, lineWidth: 0.5)
        )
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Vocab List

    private var vocabList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredVocab, id: \.key) { heard, intended in
                    HStack(spacing: AppSpacing.md) {
                        // Left accent dot
                        Circle()
                            .fill(AppColors.accent.opacity(0.5))
                            .frame(width: 5, height: 5)

                        Text(heard)
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.textPrimary)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.accent.opacity(0.5))

                        Text(intended)
                            .font(.appBody)
                            .foregroundColor(AppColors.textSecondary)

                        Spacer()

                        Button(action: { viewModel.removeVocabEntry(heard: heard) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.deleteRed.opacity(0.5))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Remove entry")
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                    .rowHover()

                    if heard != filteredVocab.last?.key {
                        Rectangle()
                            .fill(AppColors.divider)
                            .frame(height: 1)
                            .padding(.leading, AppSpacing.xl + AppSpacing.lg)
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "book")
                .font(.appEmptyIcon)
                .foregroundColor(AppColors.textMuted)
            VStack(spacing: AppSpacing.xs) {
                Text("No vocabulary entries yet")
                    .font(.appTitle)
                    .foregroundColor(AppColors.textSecondary)
                Text("Add corrections above, or say \u{201c}no, X is Y\u{201d} while dictating.")
                    .font(.appCaption)
                    .foregroundColor(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AppColors.textMuted)
            Text("No matching entries")
                .font(.appTitle)
                .foregroundColor(AppColors.textSecondary)
            Text("Try a different search term.")
                .font(.appCaption)
                .foregroundColor(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addEntry() {
        guard !newHeard.isEmpty, !newIntended.isEmpty else { return }
        viewModel.addVocabEntry(heard: newHeard, intended: newIntended)
        newHeard = ""
        newIntended = ""
    }
}
