import Foundation
import Combine

@MainActor
public final class WebViewStatusModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(message: String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var lastErrorMessage: String?

    public init() {}

    public func markLoading() {
        state = .loading
    }

    public func markReady() {
        lastErrorMessage = nil
        state = .ready
    }

    public func markFailed(_ message: String) {
        lastErrorMessage = message
        state = .failed(message: message)
    }
}
