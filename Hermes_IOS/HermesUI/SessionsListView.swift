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
        VStack(spacing: 0) {
            List {
                if isLoading && sessions.isEmpty {
                    loadingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else if searchText.isEmpty && sessions.isEmpty {
                    emptyView
                } else if isSearching {
                    if searchResults.isEmpty {
                        noResultsView
                    } else {
                        ForEach(searchResults) { result in
                            Button { openSessionInWebView(result.sessionId) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title ?? "Untitled session").font(.body).foregroundStyle(.primary).lineLimit(1)
                                    if let matchType = result.matchType {
                                        HStack(spacing: 8) {
                                            Text("Matched: \(matchType)").font(.caption2).foregroundStyle(.tertiary)
                                            if let ts = result.lastMessageAt ?? result.updatedAt {
                                                Text(formatTimestamp(ts)).font(.caption2).foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    ForEach(sessions) { session in
                        Button { openSessionInWebView(session.sessionId) } label: {
                            SessionRowView(session: session)
                        }.buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                Task { await deleteSession(session.sessionId) }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { if i < sessions.count { Task { await deleteSession(sessions[i].sessionId) } } }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await loadSessions() }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search sessions…")
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { isSearching = false }
            else { isSearching = true; Task { await performSearch() } }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !sessions.isEmpty {
                    Button { showCleanupAlert = true } label: { Image(systemName: "trash") }.disabled(isLoading)
                }
                Button { Task { await loadSessions() } } label: { Image(systemName: "arrow.clockwise") }.disabled(isLoading)
                Button { Task { await createNewSession() } } label: { Image(systemName: "plus") }.disabled(isLoading)
            }
        }
        .alert("Cleanup empty sessions", isPresented: $showCleanupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove empty", role: .destructive) { Task { await performCleanup() } }
        } message: { Text("Remove all sessions with no messages? This cannot be undone.") }
        .task { await loadSessions() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().progressViewStyle(.circular)
            Text("Loading sessions…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var noResultsView: some View {
        HStack { Spacer(); VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
            Text("No results").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 40); Spacer() }
        .listRowBackground(Color.clear)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text("Couldn't load sessions").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadSessions() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "message").font(.title2).foregroundStyle(.secondary)
            Text("No sessions yet").font(.headline)
            Text("Tap + to start a new conversation with Hermes.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func loadSessions() async {
        guard let active = store.activeEndpoint else { errorMessage = "No server configured."; isLoading = false; return }
        isLoading = true; errorMessage = nil
        do { sessions = try await HermesGatewayClient.shared.fetchSessions(baseURL: active.url) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func performSearch() async {
        guard let active = store.activeEndpoint, !searchText.isEmpty else { return }
        do { searchResults = try await HermesGatewayClient.shared.searchSessions(baseURL: active.url, query: searchText, contentSearch: true) }
        catch { searchResults = [] }
    }

    private func deleteSession(_ sessionId: String) async {
        guard let active = store.activeEndpoint else { return }
        _ = try? await HermesGatewayClient.shared.deleteSession(baseURL: active.url, sessionId: sessionId)
        sessions.removeAll { $0.sessionId == sessionId }
    }

    private func createNewSession() async {
        guard let active = store.activeEndpoint else { return }
        if let sessionId = try? await HermesGatewayClient.shared.createSession(baseURL: active.url) {
            openSessionInWebView(sessionId)
        }
    }

    private func performCleanup() async {
        guard let active = store.activeEndpoint else { return }
        _ = try? await HermesGatewayClient.shared.cleanupEmptySessions(baseURL: active.url, zeroOnly: false)
        await loadSessions()
    }

    private func openSessionInWebView(_ sessionId: String) {
        NotificationCenter.default.post(name: .openSessionInWebView, object: nil, userInfo: ["sessionId": sessionId])
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
