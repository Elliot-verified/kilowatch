import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingUnlink = false
    @State private var showingImporter = false

    var body: some View {
        Form {
            if let account = model.account {
                Section("Linked account") {
                    LabeledContent("Utility", value: account.utilityName)
                    LabeledContent("Account", value: "•••• \(account.accountNumberLast4)")
                    LabeledContent("Service address", value: account.serviceAddress)
                    Button("Disconnect account", role: .destructive) { confirmingUnlink = true }
                }
            }

            Section {
                if let imported = model.importedFile {
                    LabeledContent("File", value: imported.sourceFileName)
                    if let first = imported.firstDate, let last = imported.lastDate {
                        LabeledContent("Covers", value: "\(Formatters.shortDate(first)) – \(Formatters.shortDate(last))")
                    }
                    LabeledContent("Readings", value: "\(imported.intervals.count)")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label(model.importedFile == nil ? "Import a Green Button file" : "Replace with another file",
                          systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Download your usage from coned.com under Usage → Download My Data (CSV or XML). Green Button files contain usage, not line items, so charge breakdowns are estimated from Con Edison's standard residential rates.")
            }

            Section {
                Picker("Home type", selection: $model.privacy.homeProfile.homeType) {
                    ForEach(HomeType.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Bedrooms: \(model.privacy.homeProfile.bedrooms)", value: $model.privacy.homeProfile.bedrooms, in: 0...6)
                Stepper("People: \(model.privacy.homeProfile.occupants)", value: $model.privacy.homeProfile.occupants, in: 1...10)
                Toggle("Central air conditioning", isOn: $model.privacy.homeProfile.hasCentralAC)
                Toggle("Electric heat", isOn: $model.privacy.homeProfile.heatsWithElectricity)
            } header: {
                Text("Your home")
            } footer: {
                Text("Used only to compare you with genuinely similar households. More detail means a fairer comparison.")
            }

            Section {
                Toggle("Compare with similar homes", isOn: $model.privacy.contributeToNeighborCohort)
                Toggle("Let friends compare with me", isOn: $model.privacy.visibleToFriends)
                Toggle("Show friends my exact usage", isOn: $model.privacy.shareExactUsageWithFriends)
                    .disabled(!model.privacy.visibleToFriends)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Neighbor comparisons are anonymous and only shown for groups of 20 or more homes. Friend comparisons require both people to opt in.")
            }
        }
        .navigationTitle("Settings")
        .greenButtonImporter(isPresented: $showingImporter)
        .confirmationDialog("Disconnect your Con Edison account?", isPresented: $confirmingUnlink, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.unlinkAccount() } }
        } message: {
            Text("Kilowatch will delete your bills and usage data and stop syncing.")
        }
    }
}
