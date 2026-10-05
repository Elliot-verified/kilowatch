import Foundation

/// Persists the last Green Button import so the app opens straight to the
/// data on the next launch. One file, JSON, in Application Support.
enum ImportStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Kilowatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("greenbutton-import.json")
    }

    static func save(_ imported: GreenButtonImport) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(imported).write(to: fileURL, options: .atomic)
    }

    static func load() -> GreenButtonImport? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GreenButtonImport.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
