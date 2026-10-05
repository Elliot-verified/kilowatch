import Foundation

/// Parses the CSV flavour of Green Button Download My Data.
///
/// Con Edison's export looks like:
///
///     Name,JANE DOE
///     Address,"214 7TH AVE APT 3B BROOKLYN NY 11215"
///     Account Number,1234567890
///     Service,Service 1
///
///     TYPE,DATE,START TIME,END TIME,USAGE,UNITS,COST,NOTES
///     Electric usage,2026-09-05,00:00,00:14,0.12,kWh,$0.03,
///     Electric usage,2026-09-05,,,10.4,kWh,$2.61,"This read was estimated"
///
/// Rows without times are daily reads from non-smart meters. Columns are
/// matched by name so other utilities' variants (START DATE / END DATE,
/// "USAGE (kWh)") also work.
enum GreenButtonCSVParser {
    static func parse(_ text: String, timeZone: TimeZone = TimeZone(identifier: "America/New_York")!) throws -> GreenButtonImport {
        var result = GreenButtonImport()
        var columns: Columns?
        let formats = DateFormats(timeZone: timeZone)

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let fields = splitCSVLine(line)

            guard let cols = columns else {
                let upper = fields.map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
                if upper.contains("TYPE") || upper.contains(where: { $0.hasPrefix("USAGE") }) {
                    columns = Columns(headers: upper)
                    continue
                }
                readPreamble(fields, into: &result)
                continue
            }

            if let interval = parseRow(fields, cols, formats) {
                result.intervals.append(interval)
            }
        }
        guard columns != nil else { throw GreenButtonError.unrecognizedFormat }
        return result
    }

    // MARK: - Columns

    struct Columns {
        var type: Int?
        var date: Int?
        var startTime: Int?
        var endDate: Int?
        var endTime: Int?
        var usage: Int?
        var units: Int?
        var cost: Int?
        var notes: Int?

        init(headers: [String]) {
            for (i, h) in headers.enumerated() {
                switch h {
                case "TYPE": type = i
                case "DATE", "START DATE": date = i
                case "START TIME": startTime = i
                case "END DATE": endDate = i
                case "END TIME": endTime = i
                case "UNITS", "UNIT": units = i
                case "COST": cost = i
                case "NOTES": notes = i
                default:
                    if h.hasPrefix("USAGE") { usage = i }
                }
            }
        }
    }

    private static func readPreamble(_ fields: [String], into result: inout GreenButtonImport) {
        guard fields.count >= 2 else { return }
        let value = fields[1].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        switch fields[0].uppercased().trimmingCharacters(in: .whitespaces) {
        case "NAME": result.customerName = value
        case "ADDRESS", "SERVICE ADDRESS": result.serviceAddress = value
        case "ACCOUNT NUMBER", "ACCOUNT": result.accountNumber = value
        default: break
        }
    }

    // MARK: - Rows

    private static func parseRow(_ f: [String], _ c: Columns, _ formats: DateFormats) -> UsageInterval? {
        func field(_ i: Int?) -> String? {
            guard let i, i < f.count else { return nil }
            let v = f[i].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        if let type = field(c.type)?.lowercased(), type.contains("gas") { return nil }
        guard let dateText = field(c.date), let day = formats.date(dateText) else { return nil }
        guard let usageText = field(c.usage), let usage = Double(usageText.replacingOccurrences(of: ",", with: "")) else { return nil }

        var kWh = usage
        if let units = field(c.units)?.lowercased() {
            if units == "wh" { kWh = usage / 1000 }
            else if units == "mwh" { kWh = usage * 1000 }
        }

        let start: Date
        let end: Date
        if let startTime = field(c.startTime), let s = formats.combine(day, time: startTime) {
            start = s
            if let endTime = field(c.endTime), let e = formats.combine(field(c.endDate).flatMap(formats.date) ?? day, time: endTime) {
                // END TIME is the last minute of the interval ("00:14"), so round up.
                var adjusted = e <= start ? e.addingTimeInterval(86_400) : e
                let seconds = adjusted.timeIntervalSince(start)
                if seconds.truncatingRemainder(dividingBy: 300) != 0 { adjusted = adjusted.addingTimeInterval(60) }
                end = adjusted
            } else {
                end = start.addingTimeInterval(900)
            }
        } else {
            start = day
            end = formats.calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }

        var cost: Double?
        if let costText = field(c.cost) {
            let cleaned = costText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            cost = Double(cleaned)
        }
        return UsageInterval(start: start, end: end, kWh: kWh, cost: cost)
    }

    // MARK: - Helpers

    struct DateFormats {
        let calendar: Calendar
        private let dateFormatters: [DateFormatter]
        private let timeFormatters: [DateFormatter]

        init(timeZone: TimeZone) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            calendar = cal
            func make(_ format: String) -> DateFormatter {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = timeZone
                f.dateFormat = format
                return f
            }
            dateFormatters = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "yyyy/MM/dd"].map(make)
            timeFormatters = ["HH:mm", "H:mm", "h:mm a", "HH:mm:ss"].map(make)
        }

        func date(_ text: String) -> Date? {
            for f in dateFormatters { if let d = f.date(from: text) { return calendar.startOfDay(for: d) } }
            return nil
        }

        func combine(_ day: Date, time: String) -> Date? {
            for f in timeFormatters {
                if let t = f.date(from: time) {
                    let comps = calendar.dateComponents([.hour, .minute, .second], from: t)
                    return calendar.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: comps.second ?? 0, of: day)
                }
            }
            return nil
        }
    }

    /// Minimal RFC 4180 splitter: handles quoted fields with commas and doubled quotes.
    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let ch = iterator.next() {
            switch ch {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}
