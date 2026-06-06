import SwiftUI

public struct SessionsListView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var sessions: [HermesGatewayClient.SessionDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else if sessions.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadSessions() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            await loadSessions()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading sessions…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Couldn't load sessions")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadSessions() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No sessions yet")
                .font(.headline)
            Text("Start a conversation with Hermes to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            ForEach(sessions) { session in
                Button {
                    openSessionInWebView(session)
                } label: {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indices in
                // TODO: delete session via API in the future
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured. Please connect to a Hermes server first."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await HermesGatewayClient.shared.fetchSessions(baseURL: active.url)
            sessions = fetched
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func openSessionInWebView(_ session: HermesGatewayClient.SessionDTO) {
        // Post notification to switch RootView to WebView with this session
        NotificationCenter.default.post(
            name: .openSessionInWebView,
            object: nil,
            userInfo: ["sessionId": session.sessionId]
        )
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: HermesGatewayClient.SessionDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title ?? "Untitled session")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let source = session.sessionSource {
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if let count = session.messageCount, count > 0 {
                        Text("\(count) messages")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let ts = session.lastMessageAt ?? session.updatedAt {
                        Text(formatTimestamp(ts))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let pinned = session.pinned, pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension Notification.Name {
    static let openSessionInWebView = Notification.Name("openSessionInWebView")
}
