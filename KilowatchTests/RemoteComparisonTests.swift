import XCTest
@testable import Kilowatch

final class RemoteComparisonTests: XCTestCase {
    func testDecodesServerComparisonResponse() throws {
        let json = """
        {"month":"2026-09",
         "neighbors":{"cohortDescription":"1-bedroom apartments in 11215","householdCount":25,
                      "periodEnd":"2026-10-01T00:00:00.000Z","yourKWh":400,"medianKWh":355.5,
                      "efficientKWh":289.2,"percentile":74},
         "friends":[{"id":"abc","displayName":"Priya","deltaFromYou":-0.2,"sharesExactUsage":true,"kWh":320},
                    {"id":"def","displayName":"Marcus","deltaFromYou":0.08,"sharesExactUsage":false,"kWh":null}]}
        """
        let decoded = try RemoteComparisonService.decoder.decode(RemoteComparisonService.ComparisonResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.neighbors?.householdCount, 25)
        XCTAssertEqual(decoded.neighbors?.percentile, 74)
        XCTAssertEqual(decoded.friends.count, 2)
        XCTAssertEqual(decoded.friends[0].kWh, 320)
        XCTAssertNil(decoded.friends[1].kWh)
    }

    func testDecodesNullNeighbors() throws {
        let json = #"{"month":"2026-09","neighbors":null,"friends":[]}"#
        let decoded = try RemoteComparisonService.decoder.decode(RemoteComparisonService.ComparisonResponse.self, from: Data(json.utf8))
        XCTAssertNil(decoded.neighbors)
    }

    func testMonthKeyUsesMidpoint() {
        let f = ISO8601DateFormatter()
        let bill = Bill(id: UUID(), periodStart: f.date(from: "2026-09-05T04:00:00Z")!, periodEnd: f.date(from: "2026-10-05T04:00:00Z")!,
                        dueDate: Date(), kWh: 1, charges: [], isEstimatedReading: false)
        XCTAssertEqual(RemoteComparisonService.monthKey(for: bill), "2026-09")
    }
}
