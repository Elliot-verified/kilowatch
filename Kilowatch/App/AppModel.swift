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
    /// Non-nil when the last comparison fetch failed. Bills still show.
    @Published private(set) var comparisonError: String?
    @Published private(set) var usingSampleComparisons = false
    @Published var privacy: PrivacySettings {
        didSet {
            Self.savePrivacy(privacy)
            Task { await pushPrivacy() }
        }
    }
    /// Set when a Green Button import fails; the UI shows it in an alert.
    @Published var importError: String?
    @Published private(set) var importedFile: GreenButtonImport?

    private var utility: UtilityDataProvider
    private let defaultUtility: UtilityDataProvider
    private var comparisons: ComparisonService
    private let sampleComparisons: ComparisonService
    private let remoteComparisons: ComparisonService?

    init(utility: UtilityDataProvider = MockUtilityDataProvider(),
         comparisons: ComparisonService = MockComparisonService(),
         remote: ComparisonService? = APIConfig.baseURL.map { RemoteComparisonService(baseURL: $0) },
         restoreImport: Bool = true) {
        self.utility = utility
        self.defaultUtility = utility
        self.comparisons = comparisons
        self.sampleComparisons = comparisons
        self.remoteComparisons = remote
        self.privacy = Self.loadPrivacy()
        if restoreImport, let saved = ImportStore.load() {
            adopt(saved)
            Task { await refresh() }
        }
    }

    // MARK: Derived

    var account: UtilityAccount? {
        if case .linked(let account) = linkState { return account }
        return nil
    }

    /// Bills newest first.
    var sortedBills: [Bill] { bills.sorted { $0.periodEnd > $1.periodEnd } }
    var currentBill: Bill? { sortedBills.first }

    /// The ZIP reported to the comparison service.
    var effectiveZip: String {
        let override = privacy.zipOverride.trimmingCharacters(in: .whitespaces)
        if override.count == 5 { return override }
        return account?.zip ?? ""
    }

    var hasRemoteComparisons: Bool { remoteComparisons != nil }

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

    // MARK: Data sources

    /// Sample-data mode: canned bills and canned comparisons, nothing sent anywhere.
    func linkAccount() async {
        linkState = .linking
        comparisons = sampleComparisons
        usingSampleComparisons = true
        do {
            let account = try await utility.linkAccount()
            linkState = .linked(account)
            await refresh()
        } catch {
            linkState = .failed(error.localizedDescription)
        }
    }

    /// Reads a Green Button file (CSV or ESPI XML) the user picked and merges
    /// it with any earlier import, so several exports build up a full history.
    func importGreenButton(from url: URL) async {
        importError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let parsed = try await Task.detached(priority: .userInitiated) {
                try GreenButtonParser.parse(data: data, fileName: name)
            }.value
            let combined = importedFile.map { $0.merging(parsed) } ?? parsed
            try ImportStore.save(combined)
            adopt(combined)
            await refresh()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func adopt(_ imported: GreenButtonImport) {
        let provider = ImportedUtilityDataProvider(imported: imported)
        utility = provider
        importedFile = imported
        linkState = .linked(provider.account)
        // Real data gets real comparisons when a backend is configured.
        if let remote = remoteComparisons {
            comparisons = remote
            usingSampleComparisons = false
        } else {
            comparisons = sampleComparisons
            usingSampleComparisons = true
        }
    }

    func unlinkAccount() async {
        if let account { try? await utility.unlink(account) }
        if !usingSampleComparisons { try? await comparisons.deleteAccount() }
        utility = defaultUtility
        comparisons = sampleComparisons
        importedFile = nil
        linkState = .notLinked
        bills = []
        dailyUsage = []
        neighborComparison = nil
        friendComparisons = []
        comparisonError = nil
    }

    // MARK: Refresh

    func refresh() async {
        guard let account else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            bills = try await utility.fetchBills(for: account)
            dailyUsage = try await utility.fetchDailyUsage(for: account, days: 30)
        } catch {
            linkState = .linked(account) // keep stale data on screen
        }
        await refreshComparisons()
    }

    func refreshComparisons() async {
        guard let current = currentBill else {
            neighborComparison = nil
            friendComparisons = []
            return
        }
        comparisonError = nil
        do {
            try await comparisons.updateProfile(zip: effectiveZip, settings: privacy)
            try await comparisons.syncUsage(bills)
            let result = try await comparisons.comparison(for: current)
            neighborComparison = privacy.contributeToNeighborCohort ? result.neighbors : nil
            friendComparisons = privacy.visibleToFriends ? result.friends : []
        } catch {
            comparisonError = error.localizedDescription
        }
    }

    private func pushPrivacy() async {
        await refreshComparisons()
    }

    // MARK: Friends

    func createInvite() async throws -> String {
        try await comparisons.createInvite()
    }

    /// Returns the new friend's name.
    func acceptInvite(code: String) async throws -> String {
        let name = try await comparisons.acceptInvite(code: code)
        await refreshComparisons()
        return name
    }

    // MARK: Settings persistence

    private static let privacyKey = "privacySettings"

    private static func loadPrivacy() -> PrivacySettings {
        guard let data = UserDefaults.standard.data(forKey: privacyKey),
              let decoded = try? JSONDecoder().decode(PrivacySettings.self, from: data) else { return PrivacySettings() }
        return decoded
    }

    private static func savePrivacy(_ settings: PrivacySettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: privacyKey)
        }
    }
}
