import SwiftUI

public struct ProjectsView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var projects: [HermesGatewayClient.ProjectDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading projects…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    errorView
                } else if projects.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadProjects() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(isLoading)
                }
            }
        }
        .task { await loadProjects() }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text(errorMessage ?? "").font(.subheadline).foregroundStyle(.secondary)
            Button("Retry") { Task { await loadProjects() } }.buttonStyle(.borderedProminent)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder").font(.title2).foregroundStyle(.secondary)
            Text("No projects yet").font(.headline)
            Text("Create a project in Hermes to see it here.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.body)
                    if let desc = project.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let path = project.path {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadProjects() }
    }

    private func loadProjects() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            isLoading = false; return
        }
        isLoading = true; errorMessage = nil
        do {
            let result = try await HermesGatewayClient.shared.fetchProjects(baseURL: active.url)
            projects = result.projects
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
