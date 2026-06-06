import Foundation
import WebKit

/// HTTP client that routes raw requests through the shared WKWebView's JS `fetch()` context,
/// bypassing ATS restrictions on native URLSession for HTTP-only endpoints.
///
/// Callers must set `webView` before making any requests:
/// ```swift
/// WebFetchClient.shared.register(webView: myWebView)
/// ```
public actor WebFetchClient {
    public static let shared = WebFetchClient()

    /// Weak reference to the active WKWebView.
    private weak var _webView: WKWebView?

    public func register(webView: WKWebView) {
        _webView = webView
    }

    public enum WebFetchError: LocalizedError {
        case noWebView
        case fetchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noWebView:
                return "WebView not available for fetch proxy"
            case .fetchFailed(let msg):
                return msg
            }
        }
    }

    public func fetchJSON<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        baseURL: URL,
        path: String,
        method: String = "GET",
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let wkWebView = _webView else {
            throw WebFetchError.noWebView
        }

        let fullURL = WebFetchClient.buildURL(baseURL: baseURL, path: path)
        var headerParts = headers.map { "\"\($0)\": \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        headerParts.append("\"Accept\": \"application/json\"")
        let headerJSON = "{ \(headerParts.joined(separator: ", ")) }"

        let js: String
        if method == "GET" {
            js = """
            (async () => {
              try {
                const r = await fetch('\(fullURL.replacingOccurrences(of: "'", with: "\\'"))', { method: 'GET', headers: \(headerJSON), credentials: 'same-origin' });
                const text = await r.text();
                return JSON.stringify({ ok: r.ok, status: r.status, text });
              } catch(e) {
                return JSON.stringify({ ok: false, status: 0, text: e.toString() });
              }
            })();
            """
        } else {
            js = """
            (async () => {
              try {
                const r = await fetch('\(fullURL.replacingOccurrences(of: "'", with: "\\'"))', { method: '\(method)', headers: \(headerJSON), credentials: 'same-origin' });
                const text = await r.text();
                return JSON.stringify({ ok: r.ok, status: r.status, text });
              } catch(e) {
                return JSON.stringify({ ok: false, status: 0, text: e.toString() });
              }
            })();
            """
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            Task { @MainActor in
                wkWebView.evaluateJavaScript(js) { result, error in
                    Task {
                        do {
                            if let error = error {
                                throw WebFetchError.fetchFailed("JS eval error: \(error.localizedDescription)")
                            }
                            guard let jsonString = result as? String,
                                  let data = jsonString.data(using: .utf8),
                                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                throw WebFetchError.fetchFailed("bad response from web fetch")
                            }
                            let ok = dict["ok"] as? Bool ?? false
                            let status = dict["status"] as? Int ?? 0
                            let text = dict["text"] as? String ?? ""
                            guard ok else {
                                throw WebFetchError.fetchFailed("HTTP \(status): \(text.prefix(200))")
                            }
                            guard let responseData = text.data(using: .utf8) else {
                                throw WebFetchError.fetchFailed("no response data")
                            }
                            let decoded = try JSONDecoder().decode(T.self, from: responseData)
                            cont.resume(returning: decoded)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    private static func buildURL(baseURL: URL, path: String) -> String {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return "\(baseURL.absoluteString)\(path)"
        }
        comps.path = path
        return comps.url?.absoluteString ?? "\(baseURL.absoluteString)\(path)"
    }
}
