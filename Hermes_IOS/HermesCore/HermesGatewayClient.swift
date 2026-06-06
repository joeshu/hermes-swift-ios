import Foundation

/// Lightweight HTTP client for calling Hermes WebUI API endpoints on the active server.
public actor HermesGatewayClient {
    public static let shared = HermesGatewayClient()

    public struct RequestDebug: Sendable {
        public let method: String
        public let url: String
        public let note: String?
        public let errorDomain: String?
        public let errorCode: Int?
        public let errorDescription: String?
    }

    private(set) var lastDebug: RequestDebug?

    public func consumeLastDebug() -> RequestDebug? {
        let d = lastDebug
        lastDebug = nil
        return d
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    public enum GatewayClientError: LocalizedError {
        case invalidBaseURL(String)
        case httpStatus(Int, String)
        case network(String)
        case decode(String)

        public var errorDescription: String? {
            switch self {
            case .invalidBaseURL(let text):
                return "Invalid server URL: \(text)"
            case .httpStatus(let code, let url):
                return "Request failed with HTTP \(code) for \(url)"
            case .network(let text):
                return text
            case .decode(let text):
                return text
            }
        }
    }

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
        enum CodingKeys: String, CodingKey { case sessionId = "session_id" }
    }

    public struct MemoryDTO: Decodable, Sendable {
        public let memory: String
        public let user: String
        public let soul: String
        public let memoryPath: String?
        public let userPath: String?
        public let soulPath: String?
        public let memoryMtime: Double?
        public let userMtime: Double?
        public let soulMtime: Double?
        public let externalNotesEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case memory, user, soul
            case memoryPath = "memory_path"
            case userPath = "user_path"
            case soulPath = "soul_path"
            case memoryMtime = "memory_mtime"
            case userMtime = "user_mtime"
            case soulMtime = "soul_mtime"
            case externalNotesEnabled = "external_notes_enabled"
        }
    }

    public struct MemoryWriteResult: Decodable, Sendable {
        public let ok: Bool
        public let section: String?
    }

    public struct SkillsDTO: Decodable, Sendable { public let skills: [SkillDTO] }

    public struct SkillDTO: Decodable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let description: String?
        public let category: String?
        public let enabled: Bool?
    }

    public struct SkillContentDTO: Decodable, Sendable {
        public let name: String?
        public let description: String?
        public let content: String?
        public let linkedFiles: [String: String]?

        enum CodingKeys: String, CodingKey {
            case name, description, content
            case linkedFiles = "linked_files"
        }
    }

    public struct SkillToggleResult: Decodable, Sendable {
        public let ok: Bool?
        public let enabled: Bool?
    }

    public struct InsightsDTO: Decodable, Sendable {
        public let totalSessions: Int
        public let totalMessages: Int
        public let totalInputTokens: Int
        public let totalOutputTokens: Int
        public let totalTokens: Int
        public let totalCost: Double
        public let models: [String: ModelStatsDTO]?
        public let dailyTokens: [String: DailyTokenDTO]?

        enum CodingKeys: String, CodingKey {
            case totalSessions = "total_sessions"
            case totalMessages = "total_messages"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case totalTokens = "total_tokens"
            case totalCost = "total_cost"
            case models, dailyTokens = "daily_tokens"
        }
    }

    public struct ModelStatsDTO: Decodable, Sendable {
        public let sessions: Int?
        public let messages: Int?
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let cost: Double?

        enum CodingKeys: String, CodingKey {
            case sessions, messages, cost
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    public struct DailyTokenDTO: Decodable, Sendable {
        public let input: Int?
        public let output: Int?
        public let total: Int?
    }

    public struct ProfilesDTO: Decodable, Sendable {
        public let profiles: [ProfileDTO]
        public let active: String?
    }

    public struct ProfileDTO: Decodable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let path: String?
        public let isDefault: Bool?

        enum CodingKeys: String, CodingKey {
            case name, path
            case isDefault = "is_default"
        }
    }

    public struct ProjectsDTO: Decodable, Sendable {
        public let projects: [ProjectDTO]
        public let activeProfile: String?

        enum CodingKeys: String, CodingKey {
            case projects
            case activeProfile = "active_profile"
        }
    }

    public struct ProjectDTO: Decodable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let path: String?
        public let description: String?
        public let profile: String?
    }

    // MARK: - URL helpers

    private func apiURL(from baseURL: URL, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GatewayClientError.invalidBaseURL(baseURL.absoluteString)
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw GatewayClientError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }

    private func run(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GatewayClientError.network("Non-HTTP response for \(request.url?.absoluteString ?? "unknown URL")")
            }
            guard (200...299).contains(http.statusCode) else {
                throw GatewayClientError.httpStatus(http.statusCode, request.url?.absoluteString ?? "unknown URL")
            }
            return (data, http)
        } catch let error as GatewayClientError {
            throw error
        } catch {
            let ns = error as NSError
            let url = request.url?.absoluteString ?? "unknown URL"
            throw GatewayClientError.network("\(ns.domain) \(ns.code) while loading \(url): \(ns.localizedDescription)")
        }
    }

    // MARK: - API Methods

    public func fetchSessions(baseURL: URL) async throws -> [SessionDTO] {
        let url = try apiURL(from: baseURL, path: "/api/sessions")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(SessionResponse.self, from: data).sessions
    }

    public func searchSessions(baseURL: URL, query: String, contentSearch: Bool = true) async throws -> [SessionSearchResult] {
        let url = try apiURL(
            from: baseURL,
            path: "/api/sessions/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "content", value: contentSearch ? "1" : "0")
            ]
        )
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(SearchResponse.self, from: data).sessions
    }

    public func deleteSession(baseURL: URL, sessionId: String) async throws -> Bool {
        let url = try apiURL(from: baseURL, path: "/api/session/\(sessionId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, _) = try await run(request)
        return (try? JSONDecoder().decode(DeleteResult.self, from: data).ok) ?? true
    }

    public func cleanupEmptySessions(baseURL: URL, zeroOnly: Bool = false) async throws -> CleanupResult {
        let path = zeroOnly ? "/api/sessions/cleanup_zero_message" : "/api/sessions/cleanup"
        let url = try apiURL(from: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(CleanupResult.self, from: data)
    }

    public func createSession(baseURL: URL) async throws -> String? {
        let url = try apiURL(from: baseURL, path: "/api/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": "New Session"])
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(CreateSessionResponse.self, from: data).session?.sessionId
    }

    public func fetchMemory(baseURL: URL) async throws -> MemoryDTO {
        let url = try apiURL(from: baseURL, path: "/api/memory")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(MemoryDTO.self, from: data)
    }

    public func writeMemory(baseURL: URL, section: String, content: String) async throws -> Bool {
        let url = try apiURL(from: baseURL, path: "/api/memory/write")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["section": section, "content": content])
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(MemoryWriteResult.self, from: data).ok
    }

    public func fetchSkills(baseURL: URL) async throws -> [SkillDTO] {
        let url = try apiURL(from: baseURL, path: "/api/skills")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await run(request)
            return try JSONDecoder().decode(SkillsDTO.self, from: data).skills
        } catch {
            let ns = error as NSError
            lastDebug = RequestDebug(
                method: request.httpMethod ?? "GET",
                url: url.absoluteString,
                note: "fetchSkills failed",
                errorDomain: ns.domain,
                errorCode: ns.code,
                errorDescription: error.localizedDescription
            )
            throw error
        }
    }

    public func fetchSkillContent(baseURL: URL, name: String) async throws -> SkillContentDTO {
        let url = try apiURL(from: baseURL, path: "/api/skills/content", queryItems: [URLQueryItem(name: "name", value: name)])
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(SkillContentDTO.self, from: data)
    }

    public func toggleSkill(baseURL: URL, name: String, enabled: Bool) async throws -> Bool {
        let url = try apiURL(from: baseURL, path: "/api/skills/toggle")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "enabled": enabled])
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(SkillToggleResult.self, from: data).ok ?? false
    }

    public func deleteSkill(baseURL: URL, name: String) async throws -> Bool {
        let url = try apiURL(from: baseURL, path: "/api/skills/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(DeleteResult.self, from: data).ok
    }

    public func saveSkill(baseURL: URL, name: String, content: String, category: String? = nil) async throws -> Bool {
        let url = try apiURL(from: baseURL, path: "/api/skills/save")
        var payload: [String: Any] = ["name": name, "content": content]
        if let category { payload["category"] = category }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await run(request)
        if let result = try? JSONDecoder().decode(DeleteResult.self, from: data) {
            return result.ok
        }
        return true
    }

    public func fetchInsights(baseURL: URL, days: Int = 30) async throws -> InsightsDTO {
        let url = try apiURL(from: baseURL, path: "/api/insights", queryItems: [URLQueryItem(name: "days", value: String(days))])
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(InsightsDTO.self, from: data)
    }

    public func fetchProfiles(baseURL: URL) async throws -> ProfilesDTO {
        let url = try apiURL(from: baseURL, path: "/api/profiles")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(ProfilesDTO.self, from: data)
    }

    public func fetchProjects(baseURL: URL) async throws -> ProjectsDTO {
        let url = try apiURL(from: baseURL, path: "/api/projects")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await run(request)
        return try JSONDecoder().decode(ProjectsDTO.self, from: data)
    }
}
