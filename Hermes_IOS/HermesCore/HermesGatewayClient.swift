import Foundation

/// Lightweight HTTP client for calling Hermes WebUI API endpoints on the active server.
public actor HermesGatewayClient {
    public static let shared = HermesGatewayClient()

    // MARK: - DTOs

    public struct SessionDTO: Decodable, Identifiable, Sendable {
        public var id: String { sessionId }
        public let sessionId: String
        public let title: String?
        public let source: String?
        public let sessionSource: String?
        public let lastMessageAt: Double?
        public let updatedAt: Double?
        public let createdAt: Double?
        public let messageCount: Int?
        public let pinned: Bool?
        public let archived: Bool?
        public let attention: [String: AnyDecodable]?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case title, source
            case sessionSource = "session_source"
            case lastMessageAt = "last_message_at"
            case updatedAt = "updated_at"
            case createdAt = "created_at"
            case messageCount = "message_count"
            case pinned, archived, attention
        }
    }

    public struct DeleteResult: Decodable, Sendable {
        public let ok: Bool
        public let deleted: Bool?
    }

    public struct CleanupResult: Decodable, Sendable {
        public let ok: Bool
        public let cleaned: Int?
    }

    public struct ChatStartRequest: Encodable, Sendable {
        public let sessionId: String
        public let message: String

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case message
        }
    }

    public struct ChatStartResponse: Decodable, Sendable {
        public let sessionId: String?
        public let streamId: String?
        public let ok: Bool?
        public let error: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case streamId = "stream_id"
            case ok, error
        }
    }

    public struct SessionSearchResult: Decodable, Sendable, Identifiable {
        public var id: String { sessionId }
        public let sessionId: String
        public let title: String?
        public let matchType: String?
        public let lastMessageAt: Double?
        public let updatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case title
            case matchType = "match_type"
            case lastMessageAt = "last_message_at"
            case updatedAt = "updated_at"
        }
    }

    public struct SearchResponse: Decodable, Sendable {
        public let sessions: [SessionSearchResult]
        public let content: Bool?
    }

    /// Helper to decode arbitrary JSON values.
    public struct AnyDecodable: Decodable, Sendable {
        public let value: Any
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) { value = intVal }
            else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
            else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
            else if let stringVal = try? container.decode(String.self) { value = stringVal }
            else if let arrVal = try? container.decode([AnyDecodable].self) { value = arrVal.map(\.value) }
            else if let dictVal = try? container.decode([String: AnyDecodable].self) { value = dictVal.mapValues(\.value) }
            else { value = NSNull() }
        }
    }

    private struct SessionResponse: Decodable {
        let sessions: [SessionDTO]
    }

    public struct CreateSessionResponse: Decodable, Sendable {
        public let session: CreatedSessionDTO?
        public let error: String?
    }

    public struct CreatedSessionDTO: Decodable, Sendable {
        public let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
        }
    }

    // MARK: - API Methods

    public func fetchSessions(baseURL: URL) async throws -> [SessionDTO] {
        let url = baseURL.appendingPathComponent("/api/sessions")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(SessionResponse.self, from: data)
        return decoded.sessions
    }

    public func searchSessions(baseURL: URL, query: String, contentSearch: Bool = true) async throws -> [SessionSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let url = baseURL.appendingPathComponent("/api/sessions/search?q=\(encoded)&content=\(contentSearch ? "1" : "0")")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.sessions
    }

    public func deleteSession(baseURL: URL, sessionId: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("/api/session/\(sessionId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
            return true
        }

        let result = try? JSONDecoder().decode(DeleteResult.self, from: data)
        return result?.ok ?? false
    }

    public func cleanupEmptySessions(baseURL: URL, zeroOnly: Bool = false) async throws -> CleanupResult {
        let path = zeroOnly ? "/api/sessions/cleanup_zero_message" : "/api/sessions/cleanup"
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(CleanupResult.self, from: data)
    }

    public func createSession(baseURL: URL) async throws -> String? {
        let url = baseURL.appendingPathComponent("/api/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": "New Session"])
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try? JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return response?.session?.sessionId
    }
}
