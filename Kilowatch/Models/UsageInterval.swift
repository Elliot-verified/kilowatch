import Foundation

/// Metered consumption for one interval. Con Edison smart meters report
/// 15-minute intervals; the app mostly aggregates to days.
struct UsageInterval: Identifiable, Codable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let kWh: Double

    init(id: UUID = UUID(), start: Date, end: Date, kWh: Double) {
        self.id = id
        self.start = start
        self.end = end
        self.kWh = kWh
    }
}
