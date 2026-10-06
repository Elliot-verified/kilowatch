import Foundation

struct ComparisonResult: Equatable {
    var neighbors: CohortComparison?
    var friends: [FriendComparison]
}

/// Neighbor and friend comparisons. All aggregation happens on the backend;
/// the app only ever receives summaries that already respect the user's and
/// their friends' privacy settings.
protocol ComparisonService {
    /// Reports ZIP, home profile, privacy, and display name.
    func updateProfile(zip: String, settings: PrivacySettings) async throws
    /// Reports per-period usage. The server keeps only what comparisons can use.
    func syncUsage(_ bills: [Bill]) async throws
    func comparison(for bill: Bill) async throws -> ComparisonResult
    func createInvite() async throws -> String
    /// Returns the new friend's display name.
    func acceptInvite(code: String) async throws -> String
    func deleteAccount() async throws
}

/// Canned comparisons for sample-data mode and previews. Never touches the network.
struct MockComparisonService: ComparisonService {
    func updateProfile(zip: String, settings: PrivacySettings) async throws {}
    func syncUsage(_ bills: [Bill]) async throws {}

    func comparison(for bill: Bill) async throws -> ComparisonResult {
        try await Task.sleep(for: .milliseconds(300))
        return ComparisonResult(neighbors: SampleData.neighborComparison(yourKWh: bill.kWh), friends: SampleData.friends)
    }

    func createInvite() async throws -> String { "SAMP-LE42" }
    func acceptInvite(code: String) async throws -> String { "Sample friend" }
    func deleteAccount() async throws {}
}
