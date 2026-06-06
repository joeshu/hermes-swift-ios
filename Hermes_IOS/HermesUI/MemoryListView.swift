import SwiftUI

public struct MemoryListView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var memory: HermesGatewayClient.MemoryDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = "memory"
    @State private var editContent = ""
    @State private var isEditing = false
    @State private var savingStatus: String?

    private let tabs = ["memory", "user", "soul"]

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let errorMessage {
                    errorView(message: errorMessage)
                } else {
                    contentView
                }
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isLoading {
                        Button(action: { Task { await loadMemory() } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task {
            await loadMemory()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading memory…")
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
            Text("Couldn't load memory")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadMemory() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                Text("Memory").tag("memory")
                Text("User").tag("user")
                Text("Soul").tag("soul")
            }
            .pickerStyle(.segmented)
            .padding()

            if let memory {
                let content = contentForTab(memory)
                let path = pathForTab(memory)
                let mtime = mtimeForTab(memory)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if isEditing {
                            VStack(spacing: 8) {
                                TextEditor(text: $editContent)
                                    .font(.body)
                                    .frame(minHeight: 300)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.separator, lineWidth: 1)
                                    )

                                HStack(spacing: 12) {
                                    Button("Cancel") {
                                        isEditing = false
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Save") {
                                        Task { await saveMemory() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(savingStatus == "saving")
                                }
                            }
                        } else {
                            MarkdownView(text: content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let savingStatus {
                            Text(savingStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if let mtime {
                            Text("Modified \(formatTimestamp(mtime))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadMemory()
                }

                // Bottom bar
                HStack {
                    if isEditing {
                        // editing buttons already shown inline
                    } else {
                        Spacer()
                        Button("Edit") {
                            editContent = content
                            isEditing = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func loadMemory() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            memory = try await HermesGatewayClient.shared.fetchMemory(baseURL: active.url)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveMemory() async {
        guard let active = store.activeEndpoint else { return }
        savingStatus = "saving"

        do {
            let ok = try await HermesGatewayClient.shared.writeMemory(
                baseURL: active.url,
                section: selectedTab,
                content: editContent
            )
            if ok {
                savingStatus = "Saved"
                isEditing = false
                await loadMemory()
            } else {
                savingStatus = "Failed to save"
            }
        } catch {
            savingStatus = "Error: \(error.localizedDescription)"
        }

        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); savingStatus = nil }
    }

    private func contentForTab(_ memory: HermesGatewayClient.MemoryDTO) -> String {
        switch selectedTab {
        case "user": return memory.user
        case "soul": return memory.soul
        default: return memory.memory
        }
    }

    private func pathForTab(_ memory: HermesGatewayClient.MemoryDTO) -> String? {
        switch selectedTab {
        case "user": return memory.userPath
        case "soul": return memory.soulPath
        default: return memory.memoryPath
        }
    }

    private func mtimeForTab(_ memory: HermesGatewayClient.MemoryDTO) -> Double? {
        switch selectedTab {
        case "user": return memory.userMtime
        case "soul": return memory.soulMtime
        default: return memory.memoryMtime
        }
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Simple Markdown Viewer

struct MarkdownView: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text("(empty)")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        }
    }
}
