import SwiftUI
import WebKit

/// SwiftUI wrapper that hosts the configured webui inside a `WKWebView`.
public struct HermesWebView: UIViewRepresentable {
    public let endpoint: HermesEndpoint
    public let bridge: JSBridge
    public let reconnectGeneration: Int
    public let statusModel: WebViewStatusModel?
    public let endpointStore: EndpointStore?

    public init(
        endpoint: HermesEndpoint,
        bridge: JSBridge,
        reconnectGeneration: Int = 0,
        statusModel: WebViewStatusModel? = nil,
        endpointStore: EndpointStore? = nil
    ) {
        self.endpoint = endpoint
        self.bridge = bridge
        self.reconnectGeneration = reconnectGeneration
        self.statusModel = statusModel
        self.endpointStore = endpointStore
    }

    public func makeCoordinator() -> NavigationDelegate {
        let delegate = NavigationDelegate(
            pinner: endpoint.leafCertFingerprint.map(FingerprintPinner.init),
            statusModel: statusModel,
            endpoint: endpoint,
            endpointStore: endpointStore
        )
        delegate.isMainPageLoad = true
        return delegate
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WebViewConfiguration.make(bridge: bridge, bridgeEnabled: endpoint.nativeBridgeEnabled)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        bridge.attach(to: webView)
        context.coordinator.isMainPageLoad = true
        statusModel?.markLoading()
        webView.load(makeRequest())
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != endpoint.url || context.coordinator.reconnectGeneration != reconnectGeneration {
            context.coordinator.pinner = endpoint.leafCertFingerprint.map(FingerprintPinner.init)
            context.coordinator.reconnectGeneration = reconnectGeneration
            context.coordinator.isMainPageLoad = true
            statusModel?.markLoading()
            uiView.load(makeRequest())
        }
    }

    private func makeRequest() -> URLRequest {
        URLRequest(url: endpoint.url)
    }
}
