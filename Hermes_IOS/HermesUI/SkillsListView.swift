import SwiftUI

public struct SkillsListView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var skills: [HermesGatewayClient.SkillDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSkill: HermesGatewayClient.SkillDTO?
    @State private var skillContent: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else if skills.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await loadSkills() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task { await loadSkills() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading skills…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text("Couldn't load skills").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadSkills() } }.buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench").font(.title2).foregroundStyle(.secondary)
            Text("No skills found").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            ForEach(groupedCategories.keys.sorted(), id: \.self) { category in
                Section(category) {
                    ForEach(groupedCategories[category] ?? []) { skill in
                        Button { selectedSkill = skill } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(skill.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if let desc = skill.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if let enabled = skill.enabled {
                                    Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(enabled ? .green : .secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadSkills() }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(store: store, skill: skill)
        }
    }

    private var groupedCategories: [String: [HermesGatewayClient.SkillDTO]] {
        Dictionary(grouping: skills, by: { $0.category ?? "Uncategorized" })
    }

    private func loadSkills() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            isLoading = false; return
        }
        isLoading = true; errorMessage = nil
        do {
            skills = try await HermesGatewayClient.shared.fetchSkills(baseURL: active.url)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct SkillDetailView: View {
    @EnvironmentObject var store: EndpointStore
    let skill: HermesGatewayClient.SkillDTO
    @State private var content: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if let content {
                    ScrollView {
                        Text(content)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                    }
                } else {
                    Text("No content available")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard let active = store.activeEndpoint else { return }
            do {
                let result = try await HermesGatewayClient.shared.fetchSkillContent(baseURL: active.url, name: skill.name)
                content = result.content ?? result.description
            } catch { content = "Failed to load content." }
            isLoading = false
        }
    }
}
