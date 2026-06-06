import Foundation

/// Lightweight HTTP client for calling Hermes WebUI API endpoints on the active server.
public actor HermesGatewayClient {
    public static let shared = HermesGatewayClient()

    private struct SessionResponse: Decodable {
        let sessions: [SessionDTO]
    }

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
}
