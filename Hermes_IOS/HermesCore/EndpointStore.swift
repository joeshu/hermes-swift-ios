import Foundation
import os
import Combine

/// Keychain-backed store of `HermesEndpoint`s. Also tracks the user's active selection.
/// Endpoint records live together in the same blob — all secrets, all Keychain.
@MainActor
public final class EndpointStore: ObservableObject {
    public static let shared = EndpointStore()

    @Published public private(set) var endpoints: [HermesEndpoint] = []
    @Published public private(set) var activeEndpoint: HermesEndpoint?
    @Published public private(set) var connectionEpoch: Int = 0
    @Published public private(set) var healthByURL: [String: EndpointHealth] = [:]

    private static let endpointsKey = "hermes.endpoints.v1"
    private static let activeURLKey  = "hermes.activeEndpoint.v1"
    private static let endpointHealthKey = "hermes.endpointHealth.v1"

    public init() {
        reload()
    }

    public func reload() {
        endpoints = Self.loadEndpoints()
        healthByURL = Self.loadEndpointHealth()
        if let urlString = try? Keychain.string(for: Self.activeURLKey),
           let url = URL(string: urlString),
           let match = endpoints.first(where: { $0.url == url }) {
            activeEndpoint = match
        } else {
            activeEndpoint = endpoints.first
        }
    }

    public func add(_ endpoint: HermesEndpoint, activate: Bool = true) throws {
        var current = endpoints
        current.removeAll { $0.url == endpoint.url }
        current.append(endpoint)
        try Self.saveEndpoints(current)
        endpoints = current
        if activate { try setActive(endpoint) }
    }

    public func remove(_ endpoint: HermesEndpoint) throws {
        var current = endpoints
        current.removeAll { $0.url == endpoint.url }
        try Self.saveEndpoints(current)
        endpoints = current

        healthByURL.removeValue(forKey: endpoint.url.absoluteString)
        try? Self.saveEndpointHealth(healthByURL)

        if activeEndpoint?.url == endpoint.url {
            try? Keychain.delete(Self.activeURLKey)
            activeEndpoint = endpoints.first
        }
    }

    public func setActive(_ endpoint: HermesEndpoint) throws {
        try Keychain.setString(endpoint.url.absoluteString, for: Self.activeURLKey)
        activeEndpoint = endpoint
        connectionEpoch &+= 1
    }

    public func markEndpointSuccess(_ endpoint: HermesEndpoint, message: String? = nil) {
        updateHealth(for: endpoint, status: .success, message: message)
    }

    public func markEndpointFailure(_ endpoint: HermesEndpoint, message: String? = nil) {
        updateHealth(for: endpoint, status: .failure, message: message)
    }

    public func health(for endpoint: HermesEndpoint) -> EndpointHealth? {
        healthByURL[endpoint.url.absoluteString]
    }

    private func updateHealth(for endpoint: HermesEndpoint, status: EndpointHealth.Status, message: String?) {
        healthByURL[endpoint.url.absoluteString] = EndpointHealth(status: status, message: message)
        do {
            try Self.saveEndpointHealth(healthByURL)
        } catch {
            Loggers.app.error("Failed to save endpoint health: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Persistence

    private static func loadEndpoints() -> [HermesEndpoint] {
        do {
            let data = try Keychain.data(for: endpointsKey)
            return try JSONDecoder().decode([HermesEndpoint].self, from: data)
        } catch Keychain.Error.itemNotFound {
            return []
        } catch {
            Loggers.app.error("Failed to load endpoints: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func saveEndpoints(_ endpoints: [HermesEndpoint]) throws {
        let data = try JSONEncoder().encode(endpoints)
        try Keychain.set(data, for: endpointsKey)
    }

    private static func loadEndpointHealth() -> [String: EndpointHealth] {
        do {
            let data = try Keychain.data(for: endpointHealthKey)
            return try JSONDecoder().decode([String: EndpointHealth].self, from: data)
        } catch Keychain.Error.itemNotFound {
            return [:]
        } catch {
            Loggers.app.error("Failed to load endpoint health: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func saveEndpointHealth(_ value: [String: EndpointHealth]) throws {
        let data = try JSONEncoder().encode(value)
        try Keychain.set(data, for: endpointHealthKey)
    }
}
