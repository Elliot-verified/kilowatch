import Foundation

/// A single plain-English takeaway about a bill.
struct Insight: Identifiable, Equatable {
    enum Tone { case neutral, good, warning }

    let id: UUID
    let symbol: String
    let title: String
    let detail: String
    let tone: Tone

    init(id: UUID = UUID(), symbol: String, title: String, detail: String, tone: Tone = .neutral) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.tone = tone
    }
}

/// Turns raw bill numbers into the sentences a knowledgeable friend would say.
/// Pure functions, so they are easy to unit test.
enum BillExplainer {
    static func insights(current: Bill, previous: Bill?, lastYear: Bill?) -> [Insight] {
        var out: [Insight] = []

        if let previous {
            out.append(contentsOf: monthOverMonth(current: current, previous: previous))
        }
        if let lastYear {
            out.append(yearOverYear(current: current, lastYear: lastYear))
        }
        out.append(deliveryShare(current))
        if current.isEstimatedReading {
            out.append(Insight(
                symbol: "questionmark.circle",
                title: "This bill is an estimate",
                detail: "Con Edison couldn't read your meter, so this bill is based on past usage. The next actual reading will true it up, which can cause a jump or a credit.",
                tone: .warning))
        }
        return out
    }

    static func monthOverMonth(current: Bill, previous: Bill) -> [Insight] {
        var out: [Insight] = []
        let totalDelta = current.total - previous.total
        let totalPct = previous.total > 0 ? totalDelta / previous.total : 0

        // Which category moved the most?
        let biggest = ChargeCategory.allCases
            .map { ($0, current.total(for: $0) - previous.total(for: $0)) }
            .max { abs($0.1) < abs($1.1) }

        let direction = totalDelta >= 0 ? "up" : "down"
        var detail = "Your bill is \(Formatters.currency(abs(totalDelta))) \(direction) from last period."
        if let (cat, delta) = biggest, abs(delta) > 1 {
            detail += " Most of that is \(cat.title.lowercased()) charges (\(Formatters.signedCurrency(delta)))."
        }
        out.append(Insight(
            symbol: totalDelta >= 0 ? "arrow.up.right" : "arrow.down.right",
            title: "\(Formatters.percent(abs(totalPct))) \(totalDelta >= 0 ? "higher" : "lower") than last period",
            detail: detail,
            tone: totalPct > 0.15 ? .warning : (totalDelta < 0 ? .good : .neutral)))

        // Separate usage from price so people know whether to blame themselves.
        let usagePct = previous.kWhPerDay > 0 ? (current.kWhPerDay - previous.kWhPerDay) / previous.kWhPerDay : 0
        let currentRate = current.ratePerKWh(for: .supply)
        let previousRate = previous.ratePerKWh(for: .supply)
        let ratePct = previousRate > 0 ? (currentRate - previousRate) / previousRate : 0

        if abs(usagePct) >= 0.05 {
            out.append(Insight(
                symbol: "bolt",
                title: "You used \(Formatters.percent(abs(usagePct))) \(usagePct >= 0 ? "more" : "less") per day",
                detail: "\(Formatters.kWh(current.kWhPerDay)) per day this period versus \(Formatters.kWh(previous.kWhPerDay)) last period. Comparing per day removes the effect of bills covering different numbers of days.",
                tone: usagePct > 0 ? .warning : .good))
        }
        if abs(ratePct) >= 0.05 {
            out.append(Insight(
                symbol: "tag",
                title: "Supply price \(ratePct >= 0 ? "rose" : "fell") \(Formatters.percent(abs(ratePct)))",
                detail: "Con Edison paid \(Formatters.cents(currentRate)) per kWh for your electricity, versus \(Formatters.cents(previousRate)) last period. You can't control this, but it explains part of the change.",
                tone: ratePct > 0 ? .warning : .good))
        }
        return out
    }

    static func yearOverYear(current: Bill, lastYear: Bill) -> Insight {
        let pct = lastYear.kWhPerDay > 0 ? (current.kWhPerDay - lastYear.kWhPerDay) / lastYear.kWhPerDay : 0
        return Insight(
            symbol: "calendar",
            title: "\(Formatters.percent(abs(pct))) \(pct >= 0 ? "more" : "less") than this time last year",
            detail: "Same season, so weather is roughly comparable. Last year you averaged \(Formatters.kWh(lastYear.kWhPerDay)) a day and paid \(Formatters.currency(lastYear.total)).",
            tone: pct > 0.1 ? .warning : (pct < -0.05 ? .good : .neutral))
    }

    static func deliveryShare(_ bill: Bill) -> Insight {
        let share = bill.total > 0 ? bill.total(for: .delivery) / bill.total : 0
        return Insight(
            symbol: "chart.pie",
            title: "\(Formatters.percent(share)) of this bill is delivery",
            detail: "Delivery pays for the grid and is set by regulators, so switching suppliers won't change it. All-in, you paid \(Formatters.cents(bill.effectiveRatePerKWh)) per kWh.")
    }
}
