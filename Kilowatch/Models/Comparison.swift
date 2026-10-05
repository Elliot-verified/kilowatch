import Foundation

enum HomeType: String, Codable, CaseIterable, Identifiable {
    case apartment, condo, house
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Self-reported facts used to put a household in a fair comparison cohort.
struct HomeProfile: Codable, Equatable {
    var homeType: HomeType = .apartment
    var bedrooms: Int = 1
    var occupants: Int = 2
    var hasCentralAC: Bool = false
    var heatsWithElectricity: Bool = false
}

/// How you compare with similar nearby households for one billing period.
/// Computed server-side from opted-in users; cohorts under a minimum size are
/// never returned, so no individual can be singled out.
struct CohortComparison: Codable, Equatable {
    let cohortDescription: String
    let householdCount: Int
    let periodEnd: Date
    let yourKWh: Double
    let medianKWh: Double
    /// 20th percentile of the cohort, labelled "efficient similar homes".
    let efficientKWh: Double
    /// 0...100. Lower means you used less than more of the cohort.
    let percentile: Int

    var deltaFromMedian: Double {
        medianKWh > 0 ? (yourKWh - medianKWh) / medianKWh : 0
    }
}

/// A friend who has opted in to comparing with you. Both sides must consent.
/// By default only the relative difference is shared, never the raw number.
struct FriendComparison: Identifiable, Codable, Equatable {
    let id: UUID
    let displayName: String
    /// Their usage relative to yours, normalized per bedroom. +0.15 means they use 15% more.
    let deltaFromYou: Double
    let sharesExactUsage: Bool
    let kWh: Double?
}

struct PrivacySettings: Codable, Equatable {
    var contributeToNeighborCohort = true
    var visibleToFriends = true
    var shareExactUsageWithFriends = false
    var homeProfile = HomeProfile()
}
