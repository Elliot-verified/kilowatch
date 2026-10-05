import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum LinkState: Equatable {
        case notLinked
        case linking
        case linked(UtilityAccount)
        case failed(String)
    }

    @Published private(set) var linkState: LinkState = .notLinked
    @Published private(set) var bills: [Bill] = []
    @Published private(set) var dailyUsage: [UsageInterval] = []
    @Published private(set) var neighborComparison: CohortComparison?
    @Published private(set) var friendComparisons: [FriendComparison] = []
    @Published private(set) var isRefreshing = false
    @Published var privacy = PrivacySettings() {
        didSet { Task { await pushPrivacy() } }
    }

    private let utility: UtilityDataProvider
    private let comparisons: ComparisonService

    init(utility: UtilityDataProvider = MockUtilityDataProvider(),
         comparisons: ComparisonService = MockComparisonService()) {
        self.utility = utility
        self.comparisons = comparisons
    }

    var account: UtilityAccount? {
        if case .linked(let account) = linkState { return account }
        return nil
    }

    /// Bills newest first.
    var sortedBills: [Bill] { bills.sorted { $0.periodEnd > $1.periodEnd } }
    var currentBill: Bill? { sortedBills.first }

    func previousBill(before bill: Bill) -> Bill? {
        sortedBills.first { $0.periodEnd < bill.periodEnd }
    }

    func billOneYearBefore(_ bill: Bill) -> Bill? {
        guard let target = Calendar.current.date(byAdding: .year, value: -1, to: bill.periodEnd) else { return nil }
        return bills.min { abs($0.periodEnd.timeIntervalSince(target)) < abs($1.periodEnd.timeIntervalSince(target)) }
            .flatMap { abs($0.periodEnd.timeIntervalSince(target)) < 20 * 86_400 ? $0 : nil }
    }

    func insights(for bill: Bill) -> [Insight] {
        BillExplainer.insights(current: bill,
                               previous: previousBill(before: bill),
                               lastYear: billOneYearBefore(bill))
    }

    func linkAccount() async {
        linkState = .linking
        do {
            let account = try await utility.linkAccount()
            linkState = .linked(account)
            await refresh()
        } catch {
            linkState = .failed(error.localizedDescription)
        }
    }

    func unlinkAccount() async {
        if let account { try? await utility.unlink(account) }
        linkState = .notLinked
        bills = []
        dailyUsage = []
        neighborComparison = nil
        friendComparisons = []
    }

    func refresh() async {
        guard let account else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            bills = try await utility.fetchBills(for: account)
            dailyUsage = try await utility.fetchDailyUsage(for: account, days: 30)
            if let current = currentBill {
                if privacy.contributeToNeighborCohort {
                    neighborComparison = try await comparisons.neighborComparison(
                        yourKWh: current.kWh, zip: account.zip, profile: privacy.homeProfile)
                } else {
                    neighborComparison = nil
                }
                if privacy.visibleToFriends {
                    friendComparisons = try await comparisons.friendComparisons(yourKWh: current.kWh)
                } else {
                    friendComparisons = []
                }
            }
        } catch {
            // Keep stale data on screen; surface the error non-destructively.
            linkState = .linked(account)
        }
    }

    private func pushPrivacy() async {
        try? await comparisons.updatePrivacy(privacy)
        await refresh()
    }
}
