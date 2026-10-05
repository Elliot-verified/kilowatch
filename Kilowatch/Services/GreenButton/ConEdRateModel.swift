import Foundation

/// Con Edison's standard residential electric rate (SC1), approximated.
///
/// Used to turn metered kWh into a plausible line-item breakdown when the data
/// source only gives usage. Bills built this way are flagged
/// `chargesAreEstimated` so the UI can say so. Rates change with each PSC rate
/// case and the supply price moves monthly; update these from a real bill.
struct ConEdRateModel {
    var supplyRatePerKWh = 0.112
    var merchantFunctionPerKWh = 0.0041
    var basicServiceCharge = 20.14
    var deliveryRatePerKWh = 0.1562
    var systemBenefitPerKWh = 0.0067
    var grossReceiptsTaxRate = 0.0245
    var salesTaxRate = 0.045

    static let residential = ConEdRateModel()

    func charges(kWh: Double) -> [BillCharge] {
        let supply = kWh * supplyRatePerKWh
        let merchant = kWh * merchantFunctionPerKWh
        let delivery = kWh * deliveryRatePerKWh
        let sbc = kWh * systemBenefitPerKWh
        let subtotal = supply + merchant + basicServiceCharge + delivery + sbc
        let grt = subtotal * grossReceiptsTaxRate
        let salesTax = (subtotal + grt) * salesTaxRate
        let units = "\(Int(kWh.rounded())) kWh"
        return [
            BillCharge(name: "Electricity supply", category: .supply, amount: supply,
                       detail: "\(units) @ \(Formatters.cents(supplyRatePerKWh))"),
            BillCharge(name: "Merchant function charge", category: .supply, amount: merchant,
                       detail: "Cost of buying power on your behalf"),
            BillCharge(name: "Basic service charge", category: .delivery, amount: basicServiceCharge,
                       detail: "Fixed monthly charge for your meter and account"),
            BillCharge(name: "Delivery charge", category: .delivery, amount: delivery,
                       detail: "\(units) @ \(Formatters.cents(deliveryRatePerKWh))"),
            BillCharge(name: "System benefit charge", category: .delivery, amount: sbc,
                       detail: "Funds state efficiency and clean-energy programs"),
            BillCharge(name: "GRT surcharge", category: .taxesAndFees, amount: grt,
                       detail: "\(Formatters.percent(grossReceiptsTaxRate)) gross receipts tax"),
            BillCharge(name: "NYC sales tax", category: .taxesAndFees, amount: salesTax,
                       detail: String(format: "%.1f%%", salesTaxRate * 100)),
        ]
    }

    /// Charges whose total matches a known actual total. The breakdown keeps the
    /// model's proportions; use when the file gives a bill total but no detail.
    func charges(kWh: Double, matchingTotal actual: Double) -> [BillCharge] {
        let estimated = charges(kWh: kWh)
        let estimatedTotal = estimated.reduce(0) { $0 + $1.amount }
        guard estimatedTotal > 0, actual > 0 else { return estimated }
        let factor = actual / estimatedTotal
        return estimated.map { BillCharge(id: $0.id, name: $0.name, category: $0.category, amount: $0.amount * factor, detail: $0.detail) }
    }
}
