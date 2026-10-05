import Foundation

/// Serves bills and usage from a Green Button file the user imported.
/// No network, no credentials; everything is derived on device.
struct ImportedUtilityDataProvider: UtilityDataProvider {
    let imported: GreenButtonImport
    let account: UtilityAccount

    init(imported: GreenButtonImport) {
        self.imported = imported
        self.account = Self.makeAccount(from: imported)
    }

    func linkAccount() async throws -> UtilityAccount { account }

    func fetchBills(for account: UtilityAccount) async throws -> [Bill] {
        BillBuilder.bills(from: imported)
    }

    func fetchDailyUsage(for account: UtilityAccount, days: Int) async throws -> [UsageInterval] {
        Array(BillBuilder.dailyTotals(imported.intervals).suffix(days))
    }

    func unlink(_ account: UtilityAccount) async throws {
        ImportStore.clear()
    }

    static func makeAccount(from imported: GreenButtonImport) -> UtilityAccount {
        let address = imported.serviceAddress ?? "Imported from \(imported.sourceFileName)"
        let zip = address.range(of: #"\b\d{5}\b"#, options: .regularExpression).map { String(address[$0]) } ?? ""
        let last4 = imported.accountNumber.map { String($0.suffix(4)) } ?? "file"
        return UtilityAccount(id: UUID(), utilityName: "Con Edison", accountNumberLast4: last4,
                              serviceAddress: address, zip: zip, linkedAt: imported.importedAt)
    }
}
