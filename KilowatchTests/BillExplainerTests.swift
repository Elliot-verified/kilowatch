import XCTest
@testable import Kilowatch

final class BillExplainerTests: XCTestCase {
    private func bill(kWh: Double, supplyRate: Double, daysAgo: Int, estimated: Bool = false) -> Bill {
        let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
        return SampleData.makeBill(start: start, end: end, kWh: kWh, supplyRate: supplyRate, estimated: estimated)
    }

    func testTotalsSumAcrossCategories() {
        let b = bill(kWh: 400, supplyRate: 0.12, daysAgo: 0)
        let byCategory = ChargeCategory.allCases.map { b.total(for: $0) }.reduce(0, +)
        XCTAssertEqual(b.total, byCategory, accuracy: 0.001)
    }

    func testUsageIncreaseIsAttributedToUsageNotPrice() {
        let previous = bill(kWh: 300, supplyRate: 0.12, daysAgo: 30)
        let current = bill(kWh: 400, supplyRate: 0.12, daysAgo: 0)
        let insights = BillExplainer.insights(current: current, previous: previous, lastYear: nil)
        XCTAssertTrue(insights.contains { $0.symbol == "bolt" && $0.title.contains("more") })
        XCTAssertFalse(insights.contains { $0.symbol == "tag" }, "supply price did not change")
    }

    func testPriceIncreaseIsAttributedToPriceNotUsage() {
        let previous = bill(kWh: 300, supplyRate: 0.10, daysAgo: 30)
        let current = bill(kWh: 300, supplyRate: 0.14, daysAgo: 0)
        let insights = BillExplainer.insights(current: current, previous: previous, lastYear: nil)
        XCTAssertTrue(insights.contains { $0.symbol == "tag" && $0.title.contains("rose") })
        XCTAssertFalse(insights.contains { $0.symbol == "bolt" }, "usage did not change")
    }

    func testEstimatedReadingIsFlagged() {
        let current = bill(kWh: 300, supplyRate: 0.12, daysAgo: 0, estimated: true)
        let insights = BillExplainer.insights(current: current, previous: nil, lastYear: nil)
        XCTAssertTrue(insights.contains { $0.title.contains("estimate") })
    }

    func testDeliveryShareAlwaysPresent() {
        let current = bill(kWh: 300, supplyRate: 0.12, daysAgo: 0)
        let insights = BillExplainer.insights(current: current, previous: nil, lastYear: nil)
        XCTAssertTrue(insights.contains { $0.symbol == "chart.pie" })
    }
}
