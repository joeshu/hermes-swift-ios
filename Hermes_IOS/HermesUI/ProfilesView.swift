import SwiftUI

public struct ProfilesView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var profiles: [HermesGatewayClient.ProfileDTO] = []
    @State private var activeProfile: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading profiles…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                        Text(errorMessage).font(.subheadline)
                        Button("Retry") { Task { await loadProfiles() } }.buttonStyle(.borderedProminent)
                    }
                    .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listView
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadProfiles() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(isLoading)
                }
            }
        }
        .task { await loadProfiles() }
    }

    private var listView: some View {
        List {
            ForEach(profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.body)
                        if let isDefault = profile.isDefault, isDefault {
                            Text("Default profile")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if profile.name == activeProfile {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadProfiles() }
    }

    private func loadProfiles() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            isLoading = false; return
        }
        isLoading = true; errorMessage = nil
        do {
            let result = try await HermesGatewayClient.shared.fetchProfiles(baseURL: active.url)
            profiles = result.profiles
            activeProfile = result.active
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
