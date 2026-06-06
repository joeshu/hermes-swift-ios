import SwiftUI

struct RootView: View {
    private enum LauncherUX {
        static let holdToDragSeconds: TimeInterval = 0.25
        static let tapSlop: CGFloat = 8
        static let minXRatio: CGFloat = 0.06
        static let maxXRatio: CGFloat = 0.94
        static let minYRatio: CGFloat = 0.10
        static let maxYRatio: CGFloat = 0.90
        static let edgeInset: CGFloat = 26
    }

    @EnvironmentObject var store: EndpointStore
    @State private var showingSettings = false
    @State private var showingShare = false
    @State private var currentTab: NativeTab = .sessions
    @State private var launcherXRatio: CGFloat = 0.96
    @State private var launcherYRatio: CGFloat = 0.27
    @State private var launcherTouchStart: CFTimeInterval?
    @State private var launcherIsDragging = false
    @State private var bridge = JSBridge()
    @StateObject private var webViewStatus = WebViewStatusModel()
    private let shareSheet = ShareSheetCapability()

    private enum NativeTab: String, CaseIterable {
        case sessions = "Sessions"
        case skills = "Skills"
        case memory = "Memory"
        case insights = "Insights"
        case profiles = "Profile"
        case projects = "Projects"

        var icon: String {
            switch self {
            case .sessions: return "message"
            case .skills: return "wrench"
            case .memory: return "brain"
            case .insights: return "chart.bar"
            case .profiles: return "person"
            case .projects: return "folder"
            }
        }
    }

    var body: some View {
        ZStack {
            if let active = store.activeEndpoint {
                VStack(spacing: 0) {
                    // Tab bar
                    Picker("View", selection: $currentTab) {
                        ForEach(NativeTab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.palette)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)

                    // Content
                    switch currentTab {
                    case .sessions:
                        SessionsListView()
                            .environmentObject(store)
                    case .skills:
                        SkillsListView()
                            .environmentObject(store)
                    case .memory:
                        MemoryListView()
                            .environmentObject(store)
                    case .insights:
                        InsightsView()
                            .environmentObject(store)
                    case .profiles:
                        ProfilesView()
                            .environmentObject(store)
                    case .projects:
                        ProjectsView()
                            .environmentObject(store)
                    }
                }

                launcherOverlay
            } else {
                SettingsView(store: store, connectionOnly: true)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, connectionOnly: false) {
                showingSettings = false
            }
        }
        .sheet(isPresented: $showingShare) {
            shareSheetView
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSessionInWebView)) { notification in
            openWebViewForSession(notification: notification)
        }
    }

    private var shareSheetView: some View {
        VStack(spacing: 16) {
            Text("Share")
                .font(.headline)
                .padding(.top, 20)

            if let active = store.activeEndpoint {
                Button {
                    dismissShare()
                    Task { try? await shareSheet.invoke(method: "present", params: [
                        "text": .string("Check out Hermes"),
                        "url": .string(active.url.absoluteString)
                    ]) }
                } label: {
                    Label("Share this page", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button {
                UIPasteboard.general.string = store.activeEndpoint?.url.absoluteString ?? ""
                dismissShare()
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if let active = store.activeEndpoint, let host = active.url.host {
                Button {
                    UIPasteboard.general.string = host
                    dismissShare()
                } label: {
                    Label("Copy server address", systemImage: "link")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Cancel") { dismissShare() }
                .padding(.bottom, 20)
        }
        .frame(maxWidth: 320)
    }

    private func dismissShare() {
        showingShare = false
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.15)

            Text("Connecting…")
                .font(.headline)

            if let active = store.activeEndpoint {
                Text(active.displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(20)
        .frame(maxWidth: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)
    }

    private func failureOverlay(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Connection failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Open Connections") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)

                Button("Retry") {
                    webViewStatus.markLoading()
                    if let active = store.activeEndpoint {
                        try? store.setActive(active)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)
    }

    private var launcherOverlay: some View {
        ZStack {
            if launcherTouchStart != nil || launcherIsDragging {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .zIndex(1)
            }

            GeometryReader { geo in
                ZStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                    Image(systemName: "gearshape")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                }
                .contentShape(Rectangle())
                .position(
                    x: geo.size.width * launcherXRatio,
                    y: geo.size.height * launcherYRatio
                )
                .highPriorityGesture(repositionGesture(in: geo.size, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom))
                .zIndex(2)
            }
        }
    }

    private func repositionGesture(in size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if launcherTouchStart == nil {
                    launcherTouchStart = CACurrentMediaTime()
                }

                guard holdElapsed() >= LauncherUX.holdToDragSeconds else { return }
                launcherIsDragging = true

                let clamped = clampLauncherPoint(value.location, in: size, safeTop: safeTop, safeBottom: safeBottom)
                launcherXRatio = clamped.x / max(size.width, 1)
                launcherYRatio = clamped.y / max(size.height, 1)
            }
            .onEnded { value in
                let holdTime = holdElapsed()
                let moveDistance = hypot(value.translation.width, value.translation.height)

                if holdTime < LauncherUX.holdToDragSeconds && moveDistance < LauncherUX.tapSlop {
                    showingSettings = true
                }

                if holdTime >= LauncherUX.holdToDragSeconds {
                    let clamped = clampLauncherPoint(value.location, in: size, safeTop: safeTop, safeBottom: safeBottom)
                    launcherXRatio = clamped.x / max(size.width, 1)
                    launcherYRatio = clamped.y / max(size.height, 1)
                }

                launcherTouchStart = nil
                launcherIsDragging = false
            }
    }

    private func holdElapsed() -> CFTimeInterval {
        guard let start = launcherTouchStart else { return 0 }
        return CACurrentMediaTime() - start
    }

    private func clampLauncherPoint(_ point: CGPoint, in size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> CGPoint {
        let minX = size.width * LauncherUX.minXRatio
        let maxX = size.width * LauncherUX.maxXRatio
        let minY = max(size.height * LauncherUX.minYRatio, safeTop + LauncherUX.edgeInset)
        let maxY = min(size.height * LauncherUX.maxYRatio, size.height - safeBottom - LauncherUX.edgeInset)
        let clampedX = min(max(point.x, minX), maxX)
        let clampedY = min(max(point.y, minY), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func openWebViewForSession(notification: Notification) {
        // WebView 相关方法暂不实现
    }
}
