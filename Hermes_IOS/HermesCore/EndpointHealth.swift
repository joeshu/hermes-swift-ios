import Foundation

public struct EndpointHealth: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case unknown
        case success
        case failure
    }

    public let status: Status
    public let checkedAt: Date
    public let message: String?

    public init(status: Status, checkedAt: Date = .init(), message: String? = nil) {
        self.status = status
        self.checkedAt = checkedAt
        self.message = message
    }
}
