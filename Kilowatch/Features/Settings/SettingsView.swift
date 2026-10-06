import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingUnlink = false
    @State private var showingImporter = false

    var body: some View {
        Form {
            if let account = model.account {
                Section {
                    LabeledContent("Source", value: model.importedFile == nil ? "Sample data" : "Green Button export")
                    if model.importedFile != nil {
                        LabeledContent("Account", value: "•••• \(account.accountNumberLast4)")
                        LabeledContent("Service address", value: account.serviceAddress)
                    }
                    if let imported = model.importedFile {
                        if let first = imported.firstDate, let last = imported.lastDate {
                            LabeledContent("Covers", value: "\(Formatters.shortDate(first)) – \(Formatters.shortDate(last))")
                        }
                        LabeledContent("Readings", value: "\(imported.intervals.count)")
                        ForEach(imported.allFileNames, id: \.self) { name in
                            Label(name, systemImage: "doc").foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label(model.importedFile == nil ? "Import a Green Button file" : "Import another export",
                              systemImage: "square.and.arrow.down")
                    }
                    Button(model.importedFile == nil ? "Leave sample data" : "Remove my data", role: .destructive) {
                        confirmingUnlink = true
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text(model.importedFile == nil
                         ? "You're looking at a made-up Brooklyn apartment. Import a Green Button export from coned.com (Usage → Download My Data) to see your own usage."
                         : "Exports merge, so import several to build up a full year. Green Button files contain usage, not line items, so charge breakdowns are estimated from Con Edison's standard residential rates.")
                }
            }

            Section {
                TextField("ZIP code", text: $model.privacy.zipOverride)
                    .keyboardType(.numberPad)
                if model.privacy.zipOverride.isEmpty, let zip = model.account?.zip, !zip.isEmpty {
                    LabeledContent("From your address", value: zip)
                }
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
                TextField("Name friends see", text: $model.privacy.displayName)
                Toggle("Compare with similar homes", isOn: $model.privacy.contributeToNeighborCohort)
                Toggle("Let friends compare with me", isOn: $model.privacy.visibleToFriends)
                Toggle("Show friends my exact usage", isOn: $model.privacy.shareExactUsageWithFriends)
                    .disabled(!model.privacy.visibleToFriends)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Neighbor comparisons are anonymous and only shown for groups of 20 or more homes. Friend comparisons require both people to opt in. Turning both off deletes your usage from the comparison service.")
            }
        }
        .navigationTitle("Settings")
        .greenButtonImporter(isPresented: $showingImporter)
        .confirmationDialog(model.importedFile == nil ? "Leave sample data?" : "Remove your data from this phone?",
                            isPresented: $confirmingUnlink, titleVisibility: .visible) {
            Button(model.importedFile == nil ? "Leave" : "Remove", role: .destructive) { Task { await model.unlinkAccount() } }
        } message: {
            Text(model.importedFile == nil
                 ? "You'll go back to the start screen."
                 : "Kilowatch will delete the imported usage from this phone. Your Con Edison account is not affected.")
        }
    }
}
