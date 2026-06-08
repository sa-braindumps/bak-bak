import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationView {
            List(selection: $viewModel.selectedTab) {
                ForEach(DashboardViewModel.Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)

            detailView
        }
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
