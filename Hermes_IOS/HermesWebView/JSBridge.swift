import Foundation
import os
import WebKit

/// Routes JS-side calls (window.hermes.invoke) to native iPhone capabilities.
/// Single `WKScriptMessageHandler` — every message arrives via `userContentController(_:didReceive:)`
/// with `message.name == "hermes"`.
///
/// Method format:
///   `capability.<name>.<method>` — invoke a registered HermesCapability (camera, share, notifications, ...)
///   `meta.info` — return device info (model, OS, app version)
///
/// Added:
///   `web.fetch` — performs a fetch through WKWebView JS context (bypasses ATS for native URLSession).
///     Params: { method?, headers?, body? }
///     The path is prepended with the current endpoint base URL.
///
/// Hermes-agent code running in the WKWebView calls:
///   const photo = await window.hermes.invoke("capability.camera.scanQR");
///   const me    = await window.hermes.invoke("meta.info");
public final class JSBridge: NSObject, WKScriptMessageHandler, @unchecked Sendable {

    private weak var webView: WKWebView?
    private let registry: CapabilityRegistry

    public init(registry: CapabilityRegistry = .shared) {
        self.registry = registry
    }

    public func attach(to webView: WKWebView) { self.webView = webView }

    public func userContentController(_ userContentController: WKUserContentController,
                                       didReceive message: WKScriptMessage) {
        guard message.name == "hermes",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let method = body["method"] as? String else {
            Loggers.webView.error("Malformed JS bridge message")
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.route(method: method, params: params)
                self.deliver(id: id, result: result, error: nil)
            } catch {
                self.deliver(id: id, result: nil, error: "\(error)")
            }
        }
    }

    private func route(method: String, params: [String: Any]) async throws -> AnyCodable? {
        let parts = method.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { throw CapabilityError.unknownMethod(method) }

        switch head {
        case "capability":
            guard parts.count == 3 else { throw CapabilityError.unknownMethod(method) }
            let capabilityName = parts[1]
            let methodName = parts[2]
            guard let cap = await registry.capability(named: capabilityName) else {
                throw CapabilityError.unknownMethod("unknown capability \(capabilityName)")
            }
            return try await cap.invoke(method: methodName, params: Self.codableParams(params))

        case "meta":
            return try meta(method: parts.dropFirst().joined(separator: "."))

        case "web":
            return try await web(method: parts.dropFirst().joined(separator: "."), params: params)

        default:
            throw CapabilityError.unknownMethod(method)
        }
    }

    private func web(method: String, params: [String: Any]) async throws -> AnyCodable {
        guard method == "fetch" else { throw CapabilityError.unknownMethod("web.\(method)") }
        guard let path = params["path"] as? String else {
            throw CapabilityError.missingParam("path")
        }
        let httpMethod = (params["method"] as? String) ?? "GET"
        let headers = (params["headers"] as? [String: String]) ?? [:]
        let body = params["body"] as? String

        var headerEntries = headers.map { "\"\($0.key)\": \"\($0.value.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        let fetchOptions: String
        if httpMethod == "GET" || body == nil {
            fetchOptions = "{ method: \"\(httpMethod)\", headers: { \(headerEntries) } }"
        } else {
            let escapedBody = body?.replacingOccurrences(of: "'", with: "\\'") ?? ""
            fetchOptions = "{ method: \"\(httpMethod)\", headers: { \(headerEntries), \"Content-Type\": \"application/json\" }, body: '\(escapedBody)' }"
        }

        let js = """
        (async () => {
          try {
            const r = await fetch('\(path.replacingOccurrences(of: "'", with: "\\'"))', \(fetchOptions));
            const text = await r.text();
            let json;
            try { json = JSON.parse(text); } catch(_) { json = null; }
            return JSON.stringify({ ok: r.ok, status: r.status, text, json });
          } catch(e) {
            return JSON.stringify({ ok: false, status: 0, text: e.toString(), json: null });
          }
        })();
        """

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AnyCodable, Error>) in
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(js) { result, error in
                    if let error = error {
                        cont.resume(throwing: CapabilityError.underlying("web.fetch failed: \(error.localizedDescription)"))
                        return
                    }
                    guard let jsonString = result as? String,
                          let data = jsonString.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        cont.resume(throwing: CapabilityError.underlying("web.fetch: bad response serialization"))
                        return
                    }
                    var out: [String: AnyCodable] = [:]
                    for (k, v) in dict {
                        if let s = v as? String { out[k] = .string(s) }
                        else if let b = v as? Bool { out[k] = .bool(b) }
                        else if let i = v as? Int { out[k] = .int(i) }
                        else if let d = v as? Double { out[k] = .double(d) }
                    }
                    cont.resume(returning: .object(out))
                }
            }
        }
    }

    private func meta(method: String) throws -> AnyCodable {
        switch method {
        case "info":
            let info: [String: AnyCodable] = [
                "platform":  .string("ios"),
                "appVersion": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"),
            ]
            return .object(info)
        default:
            throw CapabilityError.unknownMethod("meta.\(method)")
        }
    }

    private func deliver(id: String, result: AnyCodable?, error: String?) {
        let payload: [String: Any] = [
            "id": id,
            "result": (try? result.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }) as Any? ?? NSNull(),
            "error": error as Any? ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.hermes.deliverResponse(\(json));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private static func codableParams(_ raw: [String: Any]) throws -> CapabilityParams {
        var out: CapabilityParams = [:]
        for (k, v) in raw { out[k] = try toAnyCodable(v) }
        return out
    }

    private static func toAnyCodable(_ v: Any) throws -> AnyCodable {
        if v is NSNull { return .null }
        if let b = v as? Bool { return .bool(b) }
        if let i = v as? Int { return .int(i) }
        if let d = v as? Double { return .double(d) }
        if let s = v as? String { return .string(s) }
        if let a = v as? [Any] { return .array(try a.map(toAnyCodable)) }
        if let o = v as? [String: Any] {
            var dict: [String: AnyCodable] = [:]
            for (k, val) in o { dict[k] = try toAnyCodable(val) }
            return .object(dict)
        }
        return .null
    }
}
