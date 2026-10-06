import Foundation
import Security

/// Where the backend lives. Set `KilowatchAPIBaseURL` in Info.plist (via
/// project.yml). When absent, the app falls back to sample comparisons.
enum APIConfig {
    static var baseURL: URL? {
        // A launch argument `-KilowatchAPIBaseURL http://localhost:3000` overrides the bundled value, for local testing.
        let raw = UserDefaults.standard.string(forKey: "KilowatchAPIBaseURL")
            ?? (Bundle.main.object(forInfoDictionaryKey: "KilowatchAPIBaseURL") as? String)
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }
}

/// Minimal Keychain wrapper for the API credential.
enum KeychainStore {
    private static let service = "com.elliotwaxman.kilowatch"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for key: String) {
        delete(key)
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

enum APIError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): return message.isEmpty ? "Server error (\(code))" : message
        }
    }
}

/// Talks to the Kilowatch backend. Registers an anonymous user on first use
/// and keeps the bearer token in the Keychain. All privacy rules are enforced
/// server-side; this client just reports settings and usage.
final class RemoteComparisonService: ComparisonService {
    private let baseURL: URL
    private let session: URLSession
    private let tokenKey = "api-token"

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: ComparisonService

    func updateProfile(zip: String, settings: PrivacySettings) async throws {
        let body: [String: Any] = [
            "zip": zip,
            "displayName": settings.displayName,
            "profile": [
                "homeType": settings.homeProfile.homeType.rawValue,
                "bedrooms": settings.homeProfile.bedrooms,
                "occupants": settings.homeProfile.occupants,
                "hasCentralAC": settings.homeProfile.hasCentralAC,
                "heatsWithElectricity": settings.homeProfile.heatsWithElectricity,
            ],
            "privacy": [
                "contributeToNeighborCohort": settings.contributeToNeighborCohort,
                "visibleToFriends": settings.visibleToFriends,
                "shareExactUsageWithFriends": settings.shareExactUsageWithFriends,
            ],
        ]
        try await request("PUT", "/api/me", body: body)
    }

    func syncUsage(_ bills: [Bill]) async throws {
        let iso = ISO8601DateFormatter()
        let periods = bills.map { ["periodStart": iso.string(from: $0.periodStart),
                                   "periodEnd": iso.string(from: $0.periodEnd),
                                   "kWh": $0.kWh] as [String: Any] }
        try await request("PUT", "/api/me/usage", body: ["periods": periods])
    }

    func comparison(for bill: Bill) async throws -> ComparisonResult {
        let data = try await request("GET", "/api/me/comparison", query: ["month": Self.monthKey(for: bill)])
        let decoded = try Self.decoder.decode(ComparisonResponse.self, from: data)
        return ComparisonResult(neighbors: decoded.neighbors, friends: decoded.friends)
    }

    func createInvite() async throws -> String {
        struct Response: Decodable { let code: String }
        let data = try await request("POST", "/api/invites")
        return try Self.decoder.decode(Response.self, from: data).code
    }

    func acceptInvite(code: String) async throws -> String {
        struct Response: Decodable { struct Friend: Decodable { let displayName: String }; let friend: Friend }
        let data = try await request("POST", "/api/invites/accept", body: ["code": code])
        return try Self.decoder.decode(Response.self, from: data).friend.displayName
    }

    func deleteAccount() async throws {
        if KeychainStore.get(tokenKey) != nil {
            _ = try? await request("DELETE", "/api/me")
        }
        KeychainStore.delete(tokenKey)
    }

    // MARK: Plumbing

    struct ComparisonResponse: Decodable {
        let month: String
        let neighbors: CohortComparison?
        let friends: [FriendComparison]
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(s)")
        }
        return d
    }()

    /// "YYYY-MM" of the month containing the middle of the bill period, matching the server.
    static func monthKey(for bill: Bill) -> String {
        let mid = bill.periodStart.addingTimeInterval(bill.periodEnd.timeIntervalSince(bill.periodStart) / 2)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month], from: mid)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    private func token() async throws -> String {
        if let existing = KeychainStore.get(tokenKey) { return existing }
        struct Registration: Decodable { let token: String }
        let data = try await send("POST", "/api/register", query: [:], body: ["displayName": "Friend"], token: nil)
        let token = try Self.decoder.decode(Registration.self, from: data).token
        KeychainStore.set(token, for: tokenKey)
        return token
    }

    @discardableResult
    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        let t = try await token()
        do {
            return try await send(method, path, query: query, body: body, token: t)
        } catch APIError.http(401, _) {
            // Server no longer knows this token (e.g. data was wiped). Re-register once.
            KeychainStore.delete(tokenKey)
            let fresh = try await token()
            return try await send(method, path, query: query, body: body, token: fresh)
        }
    }

    private func send(_ method: String, _ path: String, query: [String: String], body: [String: Any]?, token: String?) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            struct Err: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(Err.self, from: data))?.error ?? ""
            throw APIError.http(code, message)
        }
        return data
    }
}
