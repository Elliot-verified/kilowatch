import Foundation

/// A linked utility account. Kilowatch never holds the customer's Con Edison
/// password; linking happens through an authorized data-sharing flow and the
/// backend stores only an access token. The app sees this summary.
struct UtilityAccount: Identifiable, Equatable, Codable {
    let id: UUID
    let utilityName: String
    let accountNumberLast4: String
    let serviceAddress: String
    let zip: String
    let linkedAt: Date
}
