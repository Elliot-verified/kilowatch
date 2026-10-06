import Foundation

/// Deterministic fake data shaped like a real Con Edison residential account,
/// used by the mock providers and SwiftUI previews.
enum SampleData {
    static let account = UtilityAccount(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        utilityName: "Con Edison",
        accountNumberLast4: "4821",
        serviceAddress: "214 7th Ave, Apt 3B, Brooklyn, NY",
        zip: "11215",
        linkedAt: Date())

    /// Twelve monthly bills ending with the most recent full period.
    static let bills: [Bill] = {
        let cal = Calendar.current
        let today = Date()
        // Seasonal kWh profile for a Brooklyn apartment with window ACs.
        let seasonal: [Int: Double] = [1: 310, 2: 290, 3: 270, 4: 250, 5: 280, 6: 420,
                                       7: 560, 8: 590, 9: 410, 10: 280, 11: 270, 12: 300]
        // Supply price (¢/kWh) drifts; summer peaks.
        let supplyRate: [Int: Double] = [1: 0.128, 2: 0.121, 3: 0.102, 4: 0.094, 5: 0.097, 6: 0.118,
                                         7: 0.141, 8: 0.136, 9: 0.112, 10: 0.099, 11: 0.108, 12: 0.124]
        return (0..<12).reversed().map { monthsAgo -> Bill in
            let end = cal.date(byAdding: .month, value: -monthsAgo, to: cal.startOfDay(for: today))!
            let start = cal.date(byAdding: .day, value: -30, to: end)!
            let month = cal.component(.month, from: end)
            let kWh = (seasonal[month] ?? 300) * (monthsAgo == 0 ? 1.12 : 1.0)
            return makeBill(start: start, end: end, kWh: kWh, supplyRate: supplyRate[month] ?? 0.11,
                            estimated: monthsAgo == 3)
        }
    }()

    static func makeBill(start: Date, end: Date, kWh: Double, supplyRate: Double, estimated: Bool = false) -> Bill {
        var rates = ConEdRateModel.residential
        rates.supplyRatePerKWh = supplyRate
        var charges = rates.charges(kWh: kWh)
        if estimated {
            charges.append(BillCharge(name: "Estimated reading", category: .adjustments, amount: 0,
                                      detail: "Meter was not read this period"))
        }
        return Bill(id: UUID(), periodStart: start, periodEnd: end,
                    dueDate: Calendar.current.date(byAdding: .day, value: 21, to: end)!,
                    kWh: kWh, charges: charges, isEstimatedReading: estimated)
    }

    /// Last 30 days of daily usage with a weekend bump.
    static let dailyUsage: [UsageInterval] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).reversed().map { daysAgo in
            let start = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let weekday = cal.component(.weekday, from: start)
            let base = 9.5 + sin(Double(daysAgo) / 4.0) * 2.0
            let weekend = (weekday == 1 || weekday == 7) ? 3.0 : 0
            return UsageInterval(start: start, end: end, kWh: max(3, base + weekend))
        }
    }()

    static func neighborComparison(yourKWh: Double) -> CohortComparison {
        CohortComparison(
            cohortDescription: "1-bedroom apartments in 11215",
            householdCount: 412,
            periodEnd: Date(),
            yourKWh: yourKWh,
            medianKWh: yourKWh * 0.86,
            efficientKWh: yourKWh * 0.61,
            percentile: 68)
    }

    static let friends: [FriendComparison] = [
        FriendComparison(id: "sample-priya", displayName: "Priya", deltaFromYou: -0.22, sharesExactUsage: true, kWh: 245),
        FriendComparison(id: "sample-marcus", displayName: "Marcus", deltaFromYou: 0.08, sharesExactUsage: false, kWh: nil),
        FriendComparison(id: "sample-dana", displayName: "Dana", deltaFromYou: -0.05, sharesExactUsage: false, kWh: nil),
    ]
}
