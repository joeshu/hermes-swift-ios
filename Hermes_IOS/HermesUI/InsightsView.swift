import SwiftUI

public struct InsightsView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var insights: HermesGatewayClient.InsightsDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading insights…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                        Text("Couldn't load insights").font(.headline)
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadInsights() } }.buttonStyle(.borderedProminent)
                    }
                    .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    contentView
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadInsights() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(isLoading)
                }
            }
        }
        .task { await loadInsights() }
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let insights {
                    // Summary cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Sessions", value: "\(insights.totalSessions)", icon: "message")
                        StatCard(title: "Messages", value: "\(insights.totalMessages)", icon: "text.bubble")
                        StatCard(title: "Input tokens", value: formatNumber(insights.totalInputTokens), icon: "arrow.down.doc")
                        StatCard(title: "Output tokens", value: formatNumber(insights.totalOutputTokens), icon: "arrow.up.doc")
                    }
                    .padding(.horizontal)

                    // Total tokens card
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "sum").foregroundStyle(.blue)
                            Text("Total tokens")
                            Spacer()
                            Text(formatNumber(insights.totalTokens)).fontWeight(.semibold)
                        }
                        HStack {
                            Image(systemName: "dollarsign.circle").foregroundStyle(.green)
                            Text("Estimated cost")
                            Spacer()
                            Text("$\(String(format: "%.4f", insights.totalCost))").fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Model breakdown
                    if let models = insights.models?.sorted(by: { $0.key < $1.key }), !models.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Models").font(.headline).padding(.horizontal)

                            ForEach(models, id: \.key) { model, stats in
                                HStack {
                                    Text(model).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text("\(stats.sessions ?? 0) sessions")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(formatNumber((stats.inputTokens ?? 0) + (stats.outputTokens ?? 0)))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable { await loadInsights() }
    }

    private func loadInsights() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            isLoading = false; return
        }
        isLoading = true; errorMessage = nil
        do {
            insights = try await HermesGatewayClient.shared.fetchInsights(baseURL: active.url)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(.blue)
            Text(value).font(.title2).fontWeight(.bold)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
