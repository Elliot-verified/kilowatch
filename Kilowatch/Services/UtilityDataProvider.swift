import Foundation

enum UtilityLinkError: LocalizedError {
    case cancelled
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Linking was cancelled."
        case .unavailable(let reason): return reason
        }
    }
}

/// Source of utility account, bill, and interval data.
///
/// The production implementation talks to the Kilowatch backend, which in turn
/// holds the authorization the customer granted through Con Edison's
/// data-sharing flow (or a utility-data aggregator). The app never sees or
/// stores the customer's Con Edison login.
protocol UtilityDataProvider {
    /// Starts the account-linking flow (web auth) and returns the linked account.
    func linkAccount() async throws -> UtilityAccount
    func fetchBills(for account: UtilityAccount) async throws -> [Bill]
    func fetchDailyUsage(for account: UtilityAccount, days: Int) async throws -> [UsageInterval]
    func unlink(_ account: UtilityAccount) async throws
}

/// Returns canned data after a short delay so the UI can be built and
/// demoed before the backend exists.
struct MockUtilityDataProvider: UtilityDataProvider {
    var linkDelay: Duration = .seconds(1.5)

    func linkAccount() async throws -> UtilityAccount {
        try await Task.sleep(for: linkDelay)
        return SampleData.account
    }

    func fetchBills(for account: UtilityAccount) async throws -> [Bill] {
        try await Task.sleep(for: .milliseconds(300))
        return SampleData.bills
    }

    func fetchDailyUsage(for account: UtilityAccount, days: Int) async throws -> [UsageInterval] {
        try await Task.sleep(for: .milliseconds(300))
        return Array(SampleData.dailyUsage.suffix(days))
    }

    func unlink(_ account: UtilityAccount) async throws {}
}
