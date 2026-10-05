import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.linkState {
        case .linked:
            TabView {
                NavigationStack { DashboardView() }
                    .tabItem { Label("Home", systemImage: "house") }
                NavigationStack { BillsListView() }
                    .tabItem { Label("Bills", systemImage: "doc.text") }
                NavigationStack { CompareView() }
                    .tabItem { Label("Compare", systemImage: "person.2") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        default:
            ConnectAccountView()
        }
    }
}

#Preview {
    RootView().environmentObject(AppModel())
}
