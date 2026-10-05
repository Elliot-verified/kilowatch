import Foundation

/// Parses the ESPI Atom XML flavour of Green Button.
///
/// The feed is a list of `entry` elements whose `content` holds one ESPI
/// entity each: UsagePoint, ReadingType, IntervalBlock, ElectricPowerUsageSummary.
/// Readings are integers scaled by the most recent ReadingType's
/// `powerOfTenMultiplier`; uom 72 is watt-hours. Costs are in 1/100000 of a
/// dollar. Timestamps are Unix epoch seconds.
///
/// Simplification: feeds associate ReadingTypes with IntervalBlocks through
/// link URLs. Real exports list the ReadingType immediately before its blocks,
/// so we apply the most recently seen one. Gas usage points (ServiceCategory
/// kind 1) are skipped the same way.
final class GreenButtonXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var result = GreenButtonImport()
    private var stack: [String] = []
    private var text = ""
    private var parseError: GreenButtonError?

    private struct ReadingType { var uom: Int?; var multiplier = 0; var flowDirection: Int? }
    private struct Reading { var start: TimeInterval?; var duration: TimeInterval?; var value: Double?; var cost: Double? }
    private struct Summary {
        var start: TimeInterval?; var duration: TimeInterval?; var billLastPeriod: Double?
        var consumptionValue: Double?; var consumptionMultiplier = 0; var consumptionUom: Int?
    }

    private var serviceKind: Int?
    private var readingType = ReadingType()
    private var pendingReadingType: ReadingType?
    private var reading: Reading?
    private var summary: Summary?

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldProcessNamespaces = true
    }

    func parse() throws -> GreenButtonImport {
        if !parser.parse() {
            if let parseError { throw parseError }
            throw GreenButtonError.malformedXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        if let parseError { throw parseError }
        return result
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
        switch elementName {
        case "ReadingType": pendingReadingType = ReadingType()
        case "IntervalReading": reading = Reading()
        case "ElectricPowerUsageSummary", "UsageSummary": summary = Summary()
        case "UsagePoint": serviceKind = nil
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { stack.removeLast(); text = "" }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        let grandparent = stack.count >= 3 ? stack[stack.count - 3] : ""

        switch (elementName, parent) {
        case ("kind", "ServiceCategory"):
            serviceKind = Int(value)
        case ("uom", "ReadingType"):
            pendingReadingType?.uom = Int(value)
        case ("powerOfTenMultiplier", "ReadingType"):
            pendingReadingType?.multiplier = Int(value) ?? 0
        case ("flowDirection", "ReadingType"):
            pendingReadingType?.flowDirection = Int(value)
        case ("ReadingType", _):
            if let p = pendingReadingType { readingType = p }
            pendingReadingType = nil

        case ("start", "timePeriod") where grandparent == "IntervalReading":
            reading?.start = TimeInterval(value)
        case ("duration", "timePeriod") where grandparent == "IntervalReading":
            reading?.duration = TimeInterval(value)
        case ("value", "IntervalReading"):
            reading?.value = Double(value)
        case ("cost", "IntervalReading"):
            reading?.cost = Double(value)
        case ("IntervalReading", _):
            finishReading()

        case ("start", "billingPeriod"):
            summary?.start = TimeInterval(value)
        case ("duration", "billingPeriod"):
            summary?.duration = TimeInterval(value)
        case ("billLastPeriod", _):
            summary?.billLastPeriod = Double(value)
        case ("value", "overallConsumptionLastPeriod"):
            summary?.consumptionValue = Double(value)
        case ("powerOfTenMultiplier", "overallConsumptionLastPeriod"):
            summary?.consumptionMultiplier = Int(value) ?? 0
        case ("uom", "overallConsumptionLastPeriod"):
            summary?.consumptionUom = Int(value)
        case ("ElectricPowerUsageSummary", _), ("UsageSummary", _):
            finishSummary()

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = .malformedXML("line \(parser.lineNumber): \(error.localizedDescription)")
    }

    // MARK: Entity completion

    private func finishReading() {
        defer { reading = nil }
        guard let r = reading, let start = r.start, let value = r.value else { return }
        if let kind = serviceKind, kind != 0 { return }                 // gas or other
        if let flow = readingType.flowDirection, flow == 19 { return }  // exported energy
        guard let kWh = Self.kWh(value: value, uom: readingType.uom, multiplier: readingType.multiplier) else { return }
        let duration = r.duration ?? 900
        result.intervals.append(UsageInterval(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + duration),
            kWh: kWh,
            cost: r.cost.map { $0 / 100_000 }))
    }

    private func finishSummary() {
        defer { summary = nil }
        guard let s = summary, let start = s.start, let duration = s.duration else { return }
        let totalKWh = s.consumptionValue.flatMap { Self.kWh(value: $0, uom: s.consumptionUom, multiplier: s.consumptionMultiplier) }
        result.summaries.append(GreenButtonImport.UsageSummary(
            periodStart: Date(timeIntervalSince1970: start),
            periodEnd: Date(timeIntervalSince1970: start + duration),
            totalCost: s.billLastPeriod.map { $0 / 100_000 },
            totalKWh: totalKWh))
    }

    /// uom 72 = Wh. A missing uom is treated as Wh, which is what every utility
    /// export in practice uses. Anything else (gas volumes, power) is skipped.
    static func kWh(value: Double, uom: Int?, multiplier: Int) -> Double? {
        switch uom {
        case nil, 72: return value * pow(10, Double(multiplier)) / 1000
        default: return nil
        }
    }
}
