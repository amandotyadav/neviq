import Foundation

/// Errors surfaced to the UI with human-readable messages. Nothing is
/// swallowed: every failure maps to one of these.
enum APIError: LocalizedError, Equatable {
    case unauthorized(String)
    case server(code: String, message: String, fields: [String: String])
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let m): m
        case .server(_, let m, let fields):
            fields.isEmpty ? m : "\(m): " + fields.map { "\($0.key) — \($0.value)" }.sorted().joined(separator: "; ")
        case .network(let m): m
        case .decoding(let m): m
        }
    }

    var code: String? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }

    /// AI-specific failures the UI should present as "Saathi unavailable".
    var isAIUnavailable: Bool {
        ["AI_UNAVAILABLE", "AI_TIMEOUT", "AI_BUSY", "AI_INVALID_OUTPUT", "RATE_LIMITED"].contains(code ?? "")
    }

    func fieldMessage(_ field: String) -> String? {
        if case .server(_, _, let fields) = self { return fields[field] }
        return nil
    }
}

/// Where the API lives. Defaults to the local dev server; can be changed in
/// Settings ▸ Developer so a physical device can reach your Mac or a deployment.
enum AppConfig {
    private static let key = "naviq.apiBaseURL"
    static let defaultBaseURL = "http://localhost:4000"

    static var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: key)
        let plist = Bundle.main.object(forInfoDictionaryKey: "NaviqAPIBaseURL") as? String
        return URL(string: stored ?? plist ?? defaultBaseURL) ?? URL(string: defaultBaseURL)!
    }

    static func setBaseURL(_ value: String?) {
        if let value, !value.isEmpty { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

final class APIClient {
    static let shared = APIClient()

    /// Called when the server rejects the session so the app can sign out.
    var onUnauthorized: (() -> Void)?
    var token: String?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = APIClient.isoFractional.date(from: s) ?? APIClient.isoPlain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(APIClient.isoFractional.string(from: date))
        }
    }

    nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    // MARK: Requests

    func get<T: Decodable & Sendable>(_ path: String, query: [String: String?] = [:]) async throws -> APIEnvelope<T> {
        try await send(path, method: "GET", query: query, body: Optional<String>.none)
    }

    func send<T: Decodable & Sendable, B: Encodable>(
        _ path: String,
        method: String,
        query: [String: String?] = [:],
        body: B?
    ) async throws -> APIEnvelope<T> {
        var components = URLComponents(url: AppConfig.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        if path.hasPrefix("/api/ai/") { request.timeoutInterval = 90 }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.network(Self.describe(error))
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response from the Naviq server.") }
        if (200..<300).contains(http.statusCode) {
            do {
                return try decoder.decode(APIEnvelope<T>.self, from: data)
            } catch {
                throw APIError.decoding("Naviq received an unexpected response. Please update the app or try again.")
            }
        }

        let body = try? decoder.decode(APIErrorBody.self, from: data)
        if http.statusCode == 401 {
            let message = body?.error.message ?? "Please sign in again."
            if token != nil && !path.hasPrefix("/api/auth/login") { onUnauthorized?() }
            throw APIError.unauthorized(message)
        }
        let fields = Dictionary((body?.error.details ?? []).map { ($0.field, $0.message) }, uniquingKeysWith: { a, _ in a })
        throw APIError.server(
            code: body?.error.code ?? "HTTP_\(http.statusCode)",
            message: body?.error.message ?? "The server returned an error (\(http.statusCode)).",
            fields: fields
        )
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            "You appear to be offline. Check your connection and try again."
        case .timedOut:
            "The Naviq server took too long to respond."
        case .cannotConnectToHost, .cannotFindHost:
            "Can't reach the Naviq server at \(AppConfig.baseURL.absoluteString). Is it running? You can change the address in Settings ▸ Developer."
        case .appTransportSecurityRequiresSecureConnection:
            "This server address must use HTTPS."
        default:
            "Network error: \(error.localizedDescription)"
        }
    }
}

/// Encodable helper for JSON bodies built from heterogeneous values.
nonisolated struct JSONBody: Encodable, @unchecked Sendable {
    private let value: Any?

    init(_ value: Any?) { self.value = value }

    /// Builds a JSON object. Use `NSNull()` or `nil` for an explicit null.
    static func object(_ fields: [String: Any?]) -> JSONBody { JSONBody(fields as Any) }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        guard let value else { try c.encodeNil(); return }
        // Unwrap nested optionals (Any holding Optional.none).
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let inner = mirror.children.first?.value else { try c.encodeNil(); return }
            try c.encode(JSONBody(inner))
            return
        }
        switch value {
        case is NSNull: try c.encodeNil()
        case let v as JSONBody: try c.encode(v)
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as Date: try c.encode(APIClient.isoFractional.string(from: v))
        // Swift nil means "not provided": omit the key. Use NSNull() to send an explicit null.
        case let v as [String: Any?]: try c.encode(v.compactMapValues { $0 }.mapValues { JSONBody($0) })
        case let v as [String: Any]: try c.encode(v.mapValues { JSONBody($0) })
        case let v as [Any?]: try c.encode(v.map { JSONBody($0) })
        case let v as [Any]: try c.encode(v.map { JSONBody($0) })
        default: throw EncodingError.invalidValue(value, .init(codingPath: c.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }
}
