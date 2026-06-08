import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detailArea
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppColors.accent)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("bak-bak")
                        .font(.appBrand)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Voice Dictation")
                        .font(.appBrandSub)
                        .foregroundColor(AppColors.textMuted)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.lg)

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
                .padding(.horizontal, AppSpacing.lg)

            // Nav items
            VStack(spacing: AppSpacing.xxs) {
                ForEach(DashboardViewModel.Tab.allCases) { tab in
                    sidebarButton(for: tab)
                }
            }
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.sm)

            Spacer()
        }
        .frame(width: 190)
        .background(AppColors.sidebarBg)
    }

    private func sidebarButton(for tab: DashboardViewModel.Tab) -> some View {
        let isSelected = viewModel.selectedTab == tab

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.selectedTab = tab
            }
        } label: {
            HStack(spacing: AppSpacing.sm + 2) {
                Image(systemName: tab.icon)
                    .font(.appNavIcon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? AppColors.accentBright : AppColors.textMuted)
                Text(tab.rawValue)
                    .font(.appHeadline)
                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md - 2)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isSelected ? AppColors.sidebarSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Area

    private var detailArea: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
    }

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedTab {
        case .home:
            HomeView(viewModel: viewModel)
        case .insights:
            InsightsView(viewModel: viewModel)
        case .dictionary:
            DictionaryView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }
}
