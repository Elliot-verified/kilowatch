import Foundation

/// Turns imported interval data into daily totals and monthly bills.
enum BillBuilder {
    /// Minimum days of data for a synthesized month to be shown as a bill.
    static let minimumDaysPerPeriod = 20

    static func dailyTotals(_ intervals: [UsageInterval], calendar: Calendar = .current) -> [UsageInterval] {
        var byDay: [Date: (kWh: Double, cost: Double?, hasCost: Bool)] = [:]
        for i in intervals {
            let day = calendar.startOfDay(for: i.start)
            var entry = byDay[day] ?? (0, nil, true)
            entry.kWh += i.kWh
            if let c = i.cost { entry.cost = (entry.cost ?? 0) + c } else { entry.hasCost = false }
            byDay[day] = entry
        }
        return byDay.keys.sorted().map { day in
            let e = byDay[day]!
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return UsageInterval(start: day, end: end, kWh: e.kWh, cost: e.hasCost ? e.cost : nil)
        }
    }

    static func bills(from imported: GreenButtonImport, calendar: Calendar = .current,
                      rates: ConEdRateModel = .residential) -> [Bill] {
        let days = dailyTotals(imported.intervals, calendar: calendar)
        guard !days.isEmpty else { return [] }

        let periods: [(start: Date, end: Date, knownTotal: Double?)]
        if !imported.summaries.isEmpty {
            periods = imported.summaries.map { ($0.periodStart, $0.periodEnd, $0.totalCost) }
        } else {
            periods = calendarMonths(covering: days, calendar: calendar).map { ($0.start, $0.end, nil) }
        }

        return periods.compactMap { period in
            let inPeriod = days.filter { $0.start >= period.start && $0.start < period.end }
            guard inPeriod.count >= minimumDaysPerPeriod || !imported.summaries.isEmpty, !inPeriod.isEmpty else { return nil }
            let kWh = inPeriod.reduce(0) { $0 + $1.kWh }
            let costs = inPeriod.compactMap(\.cost)
            let knownTotal = period.knownTotal ?? (costs.count == inPeriod.count ? costs.reduce(0, +) : nil)
            let charges = knownTotal.map { rates.charges(kWh: kWh, matchingTotal: $0) } ?? rates.charges(kWh: kWh)
            return Bill(id: UUID(),
                        periodStart: period.start,
                        periodEnd: period.end,
                        dueDate: calendar.date(byAdding: .day, value: 21, to: period.end) ?? period.end,
                        kWh: kWh,
                        charges: charges,
                        isEstimatedReading: false,
                        chargesAreEstimated: true)
        }
        .sorted { $0.periodEnd < $1.periodEnd }
    }

    private static func calendarMonths(covering days: [UsageInterval], calendar: Calendar) -> [(start: Date, end: Date)] {
        guard let first = days.first?.start, let last = days.last?.start else { return [] }
        var months: [(Date, Date)] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: first))!
        while cursor <= last {
            let next = calendar.date(byAdding: .month, value: 1, to: cursor)!
            months.append((cursor, next))
            cursor = next
        }
        return months
    }
}
