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

    /// Street address only, title-cased, for use as a screen title.
    /// "214 7TH AVE APT 3B BROOKLYN NY 11215" → "214 7th Ave".
    var shortAddress: String {
        var street = serviceAddress.components(separatedBy: ",").first ?? serviceAddress
        for marker in [" APT", " UNIT", " FL ", " #", " STE"] {
            if let r = street.range(of: marker, options: .caseInsensitive) { street = String(street[..<r.lowerBound]) }
        }
        street = street.trimmingCharacters(in: .whitespaces)
        let words = street.split(separator: " ").map { w -> String in
            let s = String(w)
            // Keep ordinals like 7TH lowercase after the digits; title-case everything else.
            if let first = s.first, first.isNumber { return s.lowercased() }
            return s.capitalized
        }
        let result = words.joined(separator: " ")
        return result.isEmpty ? "Home" : result
    }
}
