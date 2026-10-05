import Foundation

/// The buckets a Con Edison residential electric bill breaks into.
enum ChargeCategory: String, Codable, CaseIterable, Identifiable {
    case supply
    case delivery
    case taxesAndFees
    case adjustments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supply: return "Supply"
        case .delivery: return "Delivery"
        case .taxesAndFees: return "Taxes & fees"
        case .adjustments: return "Adjustments"
        }
    }

    /// Plain-English explanation shown when a user taps a category.
    var explanation: String {
        switch self {
        case .supply:
            return "The cost of the electricity itself. Con Edison buys it on the wholesale market and passes the price through with no markup, so this part swings month to month. If you use an ESCO, this is the part they bill instead."
        case .delivery:
            return "What Con Edison charges to get electricity to your home: wires, substations, meters, and the people who maintain them. These rates are set by New York's Public Service Commission and apply no matter who supplies your power."
        case .taxesAndFees:
            return "State and city sales tax, the gross receipts tax surcharge, and small regulatory fees. These are mostly a percentage of the charges above, so they rise and fall with your bill."
        case .adjustments:
            return "One-off items: late fees, bill credits, deposits, or corrections from an earlier estimated reading."
        }
    }
}

struct BillCharge: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let category: ChargeCategory
    let amount: Double
    /// e.g. "674 kWh @ 13.24¢"
    let detail: String?

    init(id: UUID = UUID(), name: String, category: ChargeCategory, amount: Double, detail: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.amount = amount
        self.detail = detail
    }
}

struct Bill: Identifiable, Codable, Equatable {
    let id: UUID
    let periodStart: Date
    let periodEnd: Date
    let dueDate: Date
    let kWh: Double
    let charges: [BillCharge]
    let isEstimatedReading: Bool
    /// True when line items were modelled from usage rather than read from the utility.
    var chargesAreEstimated: Bool = false

    var total: Double { charges.reduce(0) { $0 + $1.amount } }

    func total(for category: ChargeCategory) -> Double {
        charges.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    var days: Int {
        max(1, Calendar.current.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 1)
    }

    var kWhPerDay: Double { kWh / Double(days) }

    /// All-in cost per kWh, the number most people actually want.
    var effectiveRatePerKWh: Double { kWh > 0 ? total / kWh : 0 }

    func ratePerKWh(for category: ChargeCategory) -> Double {
        kWh > 0 ? total(for: category) / kWh : 0
    }
}
