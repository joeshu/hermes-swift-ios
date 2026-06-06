import Foundation
import Network

public enum EndpointPreflightError: LocalizedError {
    case unsupportedScheme
    case missingHost
    case invalidPort
    case timedOut
    case dnsFailed
    case connectionRefused
    case tlsFailed
    case notReachable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "Only http and https endpoints are supported."
        case .missingHost:
            return "The connection is missing a host name or IP address."
        case .invalidPort:
            return "The port is invalid."
        case .timedOut:
            return "Connection timed out. Check your network or Tailscale connection."
        case .dnsFailed:
            return "Hostname could not be resolved. Check the Tailscale IP or hostname."
        case .connectionRefused:
            return "The server refused the connection. Check whether Hermes webui is running."
        case .tlsFailed:
            return "TLS handshake failed. Check whether the server expects HTTPS and the certificate is valid."
        case .notReachable(let message):
            return message
        }
    }
}

public struct EndpointPreflightResult {
    public let url: URL
    public let host: String
    public let port: Int
}

public enum EndpointPreflight {
    public static func validate(_ url: URL, timeoutSeconds: TimeInterval = 4.0) async throws -> EndpointPreflightResult {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw EndpointPreflightError.unsupportedScheme
        }
        guard let host = url.host, !host.isEmpty else {
            throw EndpointPreflightError.missingHost
        }

        let inferredPort = url.port ?? (scheme == "https" ? 443 : 80)
        guard inferredPort > 0 && inferredPort < 65536 else {
            throw EndpointPreflightError.invalidPort
        }

        let port = NWEndpoint.Port(rawValue: UInt16(inferredPort))
        guard let nwPort = port else {
            throw EndpointPreflightError.invalidPort
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: scheme == "https" ? .tls : .tcp)
        let queue = DispatchQueue(label: "EndpointPreflight")

        return try await withCheckedThrowingContinuation { continuation in
            let finished = ManagedFlag()
            let timeoutWork = DispatchWorkItem {
                connection.cancel()
                if finished.complete() {
                    continuation.resume(throwing: EndpointPreflightError.timedOut)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutWork.cancel()
                    connection.cancel()
                    if finished.complete() {
                        continuation.resume(returning: EndpointPreflightResult(url: url, host: host, port: inferredPort))
                    }
                case .failed(let error):
                    timeoutWork.cancel()
                    connection.cancel()
                    if finished.complete() {
                        continuation.resume(throwing: mapError(error))
                    }
                case .cancelled:
                    timeoutWork.cancel()
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)
            connection.start(queue: queue)
        }
    }

    private static func mapError(_ error: NWError) -> EndpointPreflightError {
        switch error {
        case .dns:
            return .dnsFailed
        case .tls:
            return .tlsFailed
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return .connectionRefused
            case .ETIMEDOUT:
                return .timedOut
            case .EHOSTUNREACH:
                return .notReachable("Host is unreachable from this device.")
            case .ENETUNREACH:
                return .notReachable("Network is unreachable. Check Wi‑Fi/cellular and Tailscale.")
            default:
                return .notReachable("POSIX error code \(code.rawValue)")
            }
        default:
            return .notReachable(error.localizedDescription)
        }
    }
}

private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func complete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
