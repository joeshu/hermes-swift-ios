import Foundation
import os
import AVFoundation
import WebKit

/// Owns WKWebView's navigation lifecycle:
///   1. Pinning — if the active endpoint has `leafCertFingerprint`, reject TLS handshakes that
///      don't match.
///   2. Scheme allowlist — only http/https loads are permitted (no file://, no app schemes).
///   3. Failure mapping — translates NSURLError codes into actionable messages (mirrors patterns
///      used by the desktop client.
public final class NavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {

    public var pinner: FingerprintPinner?
    public var reconnectGeneration: Int = 0
    private let statusModel: WebViewStatusModel?
    private let endpoint: HermesEndpoint
    private let endpointStore: EndpointStore?
    private var isMainPageLoad = true

    public init(
        pinner: FingerprintPinner? = nil,
        statusModel: WebViewStatusModel? = nil,
        endpoint: HermesEndpoint,
        endpointStore: EndpointStore? = nil
    ) {
        self.pinner = pinner
        self.statusModel = statusModel
        self.endpoint = endpoint
        self.endpointStore = endpointStore
    }

    public func webView(_ webView: WKWebView,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let pinner else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if pinner.matches(serverTrust: trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            let message = "TLS pinning mismatch. The server certificate does not match the saved fingerprint."
            Loggers.webView.error("TLS pinning mismatch on \(challenge.protectionSpace.host, privacy: .public) — aborting.")
            Task { @MainActor in
                self.statusModel?.markFailed(message)
                self.endpointStore?.markEndpointFailure(self.endpoint, message: message)
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }

        guard ["http", "https"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }

        // Allow all same-origin navigation in the webui
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Mark loading only on the initial page load, not on in-page navigation
        if isMainPageLoad {
            Task { @MainActor in
                self.statusModel?.markLoading()
            }
            isMainPageLoad = false
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.statusModel?.markReady()
            self.endpointStore?.markEndpointSuccess(self.endpoint)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    @available(iOS 15.0, *)
    public func webView(_ webView: WKWebView,
                        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                        initiatedByFrame frame: WKFrameInfo,
                        type: WKMediaCaptureType,
                        decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        switch type {
        case .microphone:
            requestAccess(for: .audio, decisionHandler: decisionHandler)
        case .camera:
            requestAccess(for: .video, decisionHandler: decisionHandler)
        case .cameraAndMicrophone:
            requestCombinedAccess(decisionHandler: decisionHandler)
        @unknown default:
            decisionHandler(.deny)
        }
    }

    private func handleFailure(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }

        let hint: String
        switch ns.code {
        case -1022: hint = "Blocked by App Transport Security. Use HTTPS or relax ATS for development."
        case -1004: hint = "Server refused the connection. Check whether Hermes webui is running and reachable."
        case -1003: hint = "Hostname could not be resolved. Check the Tailscale IP or hostname."
        case -1001: hint = "Request timed out. Check your network or Tailscale connection."
        case -1202: hint = "TLS evaluation failed. The certificate may be untrusted or mismatched."
        default:    hint = ns.localizedDescription
        }
        Loggers.webView.error("Navigation failed (\(ns.code, privacy: .public)): \(hint, privacy: .public)")
        Task { @MainActor in
            self.statusModel?.markFailed(hint)
            self.endpointStore?.markEndpointFailure(self.endpoint, message: hint)
        }
    }

    public func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        handleFailure(error)
    }

    @available(iOS 15.0, *)
    private func requestAccess(for mediaType: AVMediaType,
                               decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            decisionHandler(.grant)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                decisionHandler(granted ? .grant : .deny)
            }
        default:
            decisionHandler(.deny)
        }
    }

    @available(iOS 15.0, *)
    private func requestCombinedAccess(decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        requestAccess(for: .video) { [weak self] cameraDecision in
            guard let self, cameraDecision == .grant else {
                decisionHandler(.deny)
                return
            }
            self.requestAccess(for: .audio, decisionHandler: decisionHandler)
        }
    }

}
