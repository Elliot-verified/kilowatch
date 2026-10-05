import Foundation

enum Formatters {
    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    static func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    static func signedCurrency(_ value: Double) -> String {
        (value >= 0 ? "+" : "-") + currency(abs(value))
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func kWh(_ value: Double) -> String {
        String(format: "%.1f kWh", value)
    }

    static func cents(_ dollarsPerKWh: Double) -> String {
        String(format: "%.1f¢", dollarsPerKWh * 100)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    /// The month a bill "belongs to": the one containing the middle of its period,
    /// so a Sep 1 – Oct 1 bill is September and a Sep 5 – Oct 5 bill is still September.
    static func billMonth(_ bill: Bill) -> String {
        let mid = bill.periodStart.addingTimeInterval(bill.periodEnd.timeIntervalSince(bill.periodStart) / 2)
        return monthYear(mid)
    }

    static func period(_ bill: Bill) -> String {
        "\(shortDate(bill.periodStart)) – \(shortDate(bill.periodEnd))"
    }
}
