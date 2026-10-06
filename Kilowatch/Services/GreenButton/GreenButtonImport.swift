import Foundation

/// Everything we could pull out of a Green Button file.
///
/// Green Button (the NAESB ESPI standard) carries metered usage and, at best,
/// a total cost per billing period. It never carries line items, so bills built
/// from an import have estimated charge breakdowns. See `BillBuilder`.
struct GreenButtonImport: Codable, Equatable {
    struct UsageSummary: Codable, Equatable {
        let periodStart: Date
        let periodEnd: Date
        /// Total billed for the period, in dollars, when the file includes it.
        let totalCost: Double?
        let totalKWh: Double?
    }

    var customerName: String?
    var serviceAddress: String?
    var accountNumber: String?
    var intervals: [UsageInterval]
    var summaries: [UsageSummary]
    var sourceFileName: String
    var importedAt: Date
    /// Every file that has contributed to this import, oldest first. Optional
    /// so earlier saved imports still decode.
    var fileNames: [String]?

    init(customerName: String? = nil, serviceAddress: String? = nil, accountNumber: String? = nil,
         intervals: [UsageInterval] = [], summaries: [UsageSummary] = [],
         sourceFileName: String = "", importedAt: Date = Date()) {
        self.customerName = customerName
        self.serviceAddress = serviceAddress
        self.accountNumber = accountNumber
        self.intervals = intervals
        self.summaries = summaries
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
    }

    var allFileNames: [String] { fileNames ?? [sourceFileName] }

    /// Combines another export with this one. Overlapping intervals are
    /// deduplicated by start time, with the newer file winning. Account details
    /// come from the newer file when it has them.
    func merging(_ other: GreenButtonImport) -> GreenButtonImport {
        var merged = other
        merged.customerName = other.customerName ?? customerName
        merged.serviceAddress = other.serviceAddress ?? serviceAddress
        merged.accountNumber = other.accountNumber ?? accountNumber
        merged.intervals = GreenButtonParser.deduplicated(other.intervals + intervals)
        var seenPeriods = Set<Date>()
        merged.summaries = (other.summaries + summaries)
            .filter { seenPeriods.insert($0.periodStart).inserted }
            .sorted { $0.periodStart < $1.periodStart }
        merged.fileNames = allFileNames.filter { $0 != other.sourceFileName } + [other.sourceFileName]
        return merged
    }

    var totalKWh: Double { intervals.reduce(0) { $0 + $1.kWh } }
    var firstDate: Date? { intervals.first?.start }
    var lastDate: Date? { intervals.last?.end }
}

enum GreenButtonError: LocalizedError, Equatable {
    case unreadable
    case unrecognizedFormat
    case noUsageData
    case malformedXML(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "That file couldn't be read."
        case .unrecognizedFormat:
            return "That doesn't look like a Green Button file. Export one from coned.com under Usage → Download My Data, as CSV or XML."
        case .noUsageData:
            return "The file was read, but it has no electric usage in it."
        case .malformedXML(let detail):
            return "The XML couldn't be parsed: \(detail)"
        }
    }
}

enum GreenButtonParser {
    /// Detects the format and parses. Throws `GreenButtonError`.
    static func parse(data: Data, fileName: String) throws -> GreenButtonImport {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw GreenButtonError.unreadable
        }
        let head = text.prefix(4096)
        var result: GreenButtonImport
        if head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            result = try GreenButtonXMLParser(data: data).parse()
        } else if head.range(of: "TYPE", options: .caseInsensitive) != nil || head.range(of: "USAGE", options: .caseInsensitive) != nil {
            result = try GreenButtonCSVParser.parse(text)
        } else {
            throw GreenButtonError.unrecognizedFormat
        }
        result.sourceFileName = fileName
        result.importedAt = Date()
        result.intervals = deduplicated(result.intervals)
        guard !result.intervals.isEmpty else { throw GreenButtonError.noUsageData }
        return result
    }

    /// Sorts by start and drops repeated intervals, which utilities emit when
    /// a file spans overlapping exports.
    static func deduplicated(_ intervals: [UsageInterval]) -> [UsageInterval] {
        var seen = Set<Date>()
        return intervals
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.start).inserted }
    }
}
