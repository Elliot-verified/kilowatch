import Foundation

/// Neighbor and friend comparisons. All aggregation happens on the backend;
/// the app only ever receives summaries that already respect the user's and
/// their friends' privacy settings.
protocol ComparisonService {
    func neighborComparison(yourKWh: Double, zip: String, profile: HomeProfile) async throws -> CohortComparison?
    func friendComparisons(yourKWh: Double) async throws -> [FriendComparison]
    func updatePrivacy(_ settings: PrivacySettings) async throws
}

struct MockComparisonService: ComparisonService {
    func neighborComparison(yourKWh: Double, zip: String, profile: HomeProfile) async throws -> CohortComparison? {
        try await Task.sleep(for: .milliseconds(400))
        return SampleData.neighborComparison(yourKWh: yourKWh)
    }

    func friendComparisons(yourKWh: Double) async throws -> [FriendComparison] {
        try await Task.sleep(for: .milliseconds(400))
        return SampleData.friends
    }

    func updatePrivacy(_ settings: PrivacySettings) async throws {}
}
