import SwiftUI

public struct SessionsListView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var sessions: [HermesGatewayClient.SessionDTO] = []
    @State private var isLoading = true
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchResults: [HermesGatewayClient.SessionSearchResult] = []
    @State private var showCleanupAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search sessions…")
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        isSearching = false
                    } else {
                        isSearching = true
                        Task { await performSearch() }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !sessions.isEmpty {
                            Button { Task { await cleanupEmptySessions() } } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isLoading)
                        }

                        Button { Task { await loadSessions() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)

                        Button { Task { await createNewSession() } } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isLoading)
                    }
                }
        }
        .alert("Cleanup empty sessions", isPresented: $showCleanupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove empty", role: .destructive) {
                Task { await performCleanup() }
            }
        } message: {
            Text("Remove all sessions with no messages? This cannot be undone.")
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
            Text("Tap + to start a new conversation with Hermes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            if isSearching {
                if searchResults.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No results")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 40)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(searchResults) { result in
                        searchResultRow(result)
                    }
                }
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
                .onDelete { indexSet in
                    Task { await deleteSessions(at: indexSet) }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadSessions()
        }
    }

    private func sessionRow(_ session: HermesGatewayClient.SessionDTO) -> some View {
        Button {
            openSessionInWebView(session.sessionId)
        } label: {
            SessionRowView(session: session)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                Task { await deleteSession(session.sessionId) }
            }
        }
    }

    private func searchResultRow(_ result: HermesGatewayClient.SessionSearchResult) -> some View {
        Button {
            openSessionInWebView(result.sessionId)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Untitled session")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let matchType = result.matchType {
                        Text("Matched: \(matchType)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let ts = result.lastMessageAt ?? result.updatedAt {
                        Text(formatTimestamp(ts))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
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

    private func performSearch() async {
        guard let active = store.activeEndpoint, !searchText.isEmpty else { return }

        do {
            searchResults = try await HermesGatewayClient.shared.searchSessions(
                baseURL: active.url,
                query: searchText,
                contentSearch: true
            )
        } catch {
            searchResults = []
        }
    }

    private func deleteSession(_ sessionId: String) async {
        guard let active = store.activeEndpoint else { return }

        do {
            _ = try await HermesGatewayClient.shared.deleteSession(baseURL: active.url, sessionId: sessionId)
            sessions.removeAll { $0.sessionId == sessionId }
        } catch {
            // Error already handled on server side
        }
    }

    private func deleteSessions(at indexSet: IndexSet) async {
        for index in indexSet {
            guard index < sessions.count else { continue }
            let session = sessions[index]
            await deleteSession(session.sessionId)
        }
    }

    private func createNewSession() async {
        guard let active = store.activeEndpoint else { return }

        isLoading = true
        do {
            if let sessionId = try await HermesGatewayClient.shared.createSession(baseURL: active.url) {
                openSessionInWebView(sessionId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func cleanupEmptySessions() async {
        showCleanupAlert = true
    }

    private func performCleanup() async {
        guard let active = store.activeEndpoint else { return }

        do {
            _ = try await HermesGatewayClient.shared.cleanupEmptySessions(baseURL: active.url, zeroOnly: false)
            await loadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openSessionInWebView(_ sessionId: String) {
        NotificationCenter.default.post(
            name: .openSessionInWebView,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
