import XCTest
@testable import Kilowatch

final class GreenButtonParserTests: XCTestCase {
    static let conEdCSV = """
    Name,JANE DOE
    Address,"214 7TH AVE APT 3B BROOKLYN NY 11215"
    Account Number,1234567890
    Service,Service 1

    TYPE,DATE,START TIME,END TIME,USAGE,UNITS,COST,NOTES
    Electric usage,2026-09-05,00:00,00:14,0.12,kWh,$0.03,
    Electric usage,2026-09-05,00:15,00:29,0.08,kWh,$0.02,
    Electric usage,2026-09-05,23:45,23:59,0.30,kWh,$0.08,
    Gas usage,2026-09-05,,,1.2,therms,$1.90,
    Electric usage,2026-09-06,,,10.4,kWh,$2.61,"This read was estimated"
    Electric usage,2026-09-05,00:00,00:14,0.12,kWh,$0.03,
    """

    static let espiXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:espi="http://naesb.org/espi">
      <title>Green Button Usage Feed</title>
      <entry><content><espi:UsagePoint>
        <espi:ServiceCategory><espi:kind>0</espi:kind></espi:ServiceCategory>
      </espi:UsagePoint></content></entry>
      <entry><content><espi:ReadingType>
        <espi:flowDirection>1</espi:flowDirection>
        <espi:intervalLength>900</espi:intervalLength>
        <espi:powerOfTenMultiplier>0</espi:powerOfTenMultiplier>
        <espi:uom>72</espi:uom>
      </espi:ReadingType></content></entry>
      <entry><content><espi:IntervalBlock>
        <espi:interval><espi:duration>1800</espi:duration><espi:start>1700000000</espi:start></espi:interval>
        <espi:IntervalReading>
          <espi:cost>2500</espi:cost>
          <espi:timePeriod><espi:duration>900</espi:duration><espi:start>1700000000</espi:start></espi:timePeriod>
          <espi:value>125</espi:value>
        </espi:IntervalReading>
        <espi:IntervalReading>
          <espi:timePeriod><espi:duration>900</espi:duration><espi:start>1700000900</espi:start></espi:timePeriod>
          <espi:value>250</espi:value>
        </espi:IntervalReading>
      </espi:IntervalBlock></content></entry>
      <entry><content><espi:ElectricPowerUsageSummary>
        <espi:billingPeriod><espi:duration>2592000</espi:duration><espi:start>1698796800</espi:start></espi:billingPeriod>
        <espi:billLastPeriod>11087000</espi:billLastPeriod>
        <espi:overallConsumptionLastPeriod>
          <espi:powerOfTenMultiplier>0</espi:powerOfTenMultiplier>
          <espi:uom>72</espi:uom>
          <espi:value>313600</espi:value>
        </espi:overallConsumptionLastPeriod>
      </espi:ElectricPowerUsageSummary></content></entry>
    </feed>
    """

    func testCSVParsesConEdExport() throws {
        let imported = try GreenButtonParser.parse(data: Data(Self.conEdCSV.utf8), fileName: "coned.csv")
        XCTAssertEqual(imported.customerName, "JANE DOE")
        XCTAssertEqual(imported.serviceAddress, "214 7TH AVE APT 3B BROOKLYN NY 11215")
        XCTAssertEqual(imported.accountNumber, "1234567890")
        // 4 electric rows; the gas row is skipped and the duplicate first row is dropped.
        XCTAssertEqual(imported.intervals.count, 4)
        XCTAssertEqual(imported.totalKWh, 0.12 + 0.08 + 0.30 + 10.4, accuracy: 0.0001)
        XCTAssertEqual(imported.intervals[0].cost, 0.03)
        // 15-minute rows get 15-minute spans; daily rows get a full day.
        XCTAssertEqual(imported.intervals[0].end.timeIntervalSince(imported.intervals[0].start), 900)
        XCTAssertEqual(imported.intervals[3].end.timeIntervalSince(imported.intervals[3].start), 86_400)
    }

    func testXMLParsesESPIFeed() throws {
        let imported = try GreenButtonParser.parse(data: Data(Self.espiXML.utf8), fileName: "feed.xml")
        XCTAssertEqual(imported.intervals.count, 2)
        XCTAssertEqual(imported.intervals[0].kWh, 0.125, accuracy: 0.0001)
        XCTAssertEqual(imported.intervals[1].kWh, 0.25, accuracy: 0.0001)
        XCTAssertEqual(imported.intervals[0].cost!, 0.025, accuracy: 0.0001)
        XCTAssertNil(imported.intervals[1].cost)
        XCTAssertEqual(imported.intervals[0].start, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(imported.summaries.count, 1)
        XCTAssertEqual(imported.summaries[0].totalCost!, 110.87, accuracy: 0.0001)
        XCTAssertEqual(imported.summaries[0].totalKWh!, 313.6, accuracy: 0.0001)
    }

    func testPowerOfTenMultiplierScalesValues() {
        XCTAssertEqual(GreenButtonXMLParser.kWh(value: 25, uom: 72, multiplier: 3)!, 25, accuracy: 0.0001)
        XCTAssertEqual(GreenButtonXMLParser.kWh(value: 2500, uom: 72, multiplier: -3)!, 0.0025, accuracy: 0.000001)
        XCTAssertNil(GreenButtonXMLParser.kWh(value: 1, uom: 119, multiplier: 0), "gas volume is not energy")
    }

    func testUnrecognizedFileIsRejected() {
        XCTAssertThrowsError(try GreenButtonParser.parse(data: Data("hello world".utf8), fileName: "x.txt")) { error in
            XCTAssertEqual(error as? GreenButtonError, .unrecognizedFormat)
        }
    }

    func testBillBuilderGroupsDaysIntoMonths() throws {
        // 75 days of daily reads starting July 1, all 10 kWh, $2.50 each.
        var csv = "TYPE,DATE,START TIME,END TIME,USAGE,UNITS,COST,NOTES\n"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone
        for d in 0..<75 {
            let day = cal.date(byAdding: .day, value: d, to: start)!
            csv += "Electric usage,\(f.string(from: day)),,,10,kWh,$2.50,\n"
        }
        let imported = try GreenButtonParser.parse(data: Data(csv.utf8), fileName: "daily.csv")
        let bills = BillBuilder.bills(from: imported, calendar: cal)

        // July (31 days) and August (31 days) qualify; September has only 13 days.
        XCTAssertEqual(bills.count, 2)
        XCTAssertEqual(bills[0].kWh, 310, accuracy: 0.001)
        XCTAssertEqual(bills[0].total, 77.5, accuracy: 0.01, "per-interval costs sum to the bill total")
        XCTAssertTrue(bills[0].chargesAreEstimated)
        XCTAssertEqual(bills[0].days, 31)

        let daily = BillBuilder.dailyTotals(imported.intervals, calendar: cal)
        XCTAssertEqual(daily.count, 75)
    }

    func testBillBuilderUsesFileSummariesWhenPresent() throws {
        let imported = try GreenButtonParser.parse(data: Data(Self.espiXML.utf8), fileName: "feed.xml")
        let bills = BillBuilder.bills(from: imported)
        // The file's billing period is used even though it has only one day of data,
        // and its stated total overrides the rate model.
        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills[0].kWh, 0.375, accuracy: 0.0001)
        XCTAssertEqual(bills[0].total, 110.87, accuracy: 0.01)
        XCTAssertEqual(bills[0].periodStart, Date(timeIntervalSince1970: 1_698_796_800))
        XCTAssertTrue(bills[0].chargesAreEstimated)
    }

    func testMergingTwoExportsDeduplicatesOverlap() throws {
        let first = try GreenButtonParser.parse(data: Data(Self.conEdCSV.utf8), fileName: "spring.csv")
        var laterCSV = "TYPE,DATE,START TIME,END TIME,USAGE,UNITS,COST,NOTES\n"
        laterCSV += "Electric usage,2026-09-05,00:00,00:14,0.99,kWh,$0.30,\n"   // overlaps first file
        laterCSV += "Electric usage,2026-09-07,,,11.0,kWh,$2.80,\n"            // new day
        let second = try GreenButtonParser.parse(data: Data(laterCSV.utf8), fileName: "fall.csv")

        let merged = first.merging(second)
        XCTAssertEqual(merged.intervals.count, 5, "4 from the first file + 1 new; the overlap is not doubled")
        XCTAssertEqual(merged.intervals.first?.kWh, 0.99, "newer file wins on overlap")
        XCTAssertEqual(merged.serviceAddress, "214 7TH AVE APT 3B BROOKLYN NY 11215", "kept from the older file")
        XCTAssertEqual(merged.allFileNames, ["spring.csv", "fall.csv"])
    }
}
