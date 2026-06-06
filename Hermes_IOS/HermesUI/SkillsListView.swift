import SwiftUI

public struct SkillsListView: View {
    @EnvironmentObject var store: EndpointStore
    @State private var skills: [HermesGatewayClient.SkillDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var debugInfo: HermesGatewayClient.RequestDebug?
    @State private var selectedSkill: HermesGatewayClient.SkillDTO?
    @State private var showDeleteAlert = false
    @State private var skillToDelete: HermesGatewayClient.SkillDTO?
    @State private var showNewSkillSheet = false
    @State private var editName = ""
    @State private var editContent = ""
    @State private var editCategory = ""
    @State private var saveStatus: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
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
        .searchable(text: .constant(""), prompt: "Search skills…")
        .task { await loadSkills() }
        .alert("Delete skill?", isPresented: $showDeleteAlert, presenting: skillToDelete) { skill in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteSkill(skill.name) } }
        } message: { skill in
            Text("Delete \"\(skill.name)\" and all its files? This cannot be undone.")
        }
        .sheet(isPresented: $showNewSkillSheet) {
            skillEditor(title: "New Skill", name: "", content: "", category: "")
        }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(store: store, skill: skill, onRefresh: { Task { await loadSkills() } })
        }
    }

    private func skillEditor(title: String, name: String, content: String, category: String) -> some View {
        NavigationStack {
            Form {
                if title == "New Skill" {
                    TextField("Skill name", text: $editName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                TextField("Category (optional)", text: $editCategory)
                    .textInputAutocapitalization(.never)
                Section("Content (SKILL.md)") {
                    TextEditor(text: $editContent)
                        .frame(minHeight: 200)
                }
                if let saveStatus {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showNewSkillSheet = false
                        editName = ""
                        editContent = ""
                        editCategory = ""
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await saveNewSkill() }
                    }
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty || editContent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            editName = name
            editContent = content
            editCategory = category
        }
    }

    private func saveNewSkill() async {
        guard let active = store.activeEndpoint else { return }
        saveStatus = "Saving…"

        do {
            let category = editCategory.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editCategory.trimmingCharacters(in: .whitespaces)
            let ok = try await HermesGatewayClient.shared.saveSkill(
                baseURL: active.url,
                name: editName.trimmingCharacters(in: .whitespaces),
                content: editContent,
                category: category
            )
            if ok {
                showNewSkillSheet = false
                editName = ""
                editContent = ""
                editCategory = ""
                await loadSkills()
            } else {
                saveStatus = "Failed to save"
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }

        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); saveStatus = nil }
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
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                Text("Couldn't load skills").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                if let debugInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Request debug")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Method: \(debugInfo.method)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("URL: \(debugInfo.url)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let note = debugInfo.note {
                            Text("Note: \(note)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let domain = debugInfo.errorDomain, let code = debugInfo.errorCode {
                            Text("Error: \(domain) \(code)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let desc = debugInfo.errorDescription {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                Button("Retry") { Task { await loadSkills() } }.buttonStyle(.borderedProminent)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench").font(.title2).foregroundStyle(.secondary)
            Text("No skills found").font(.headline)
            Text("Tap + to create your first skill.").font(.subheadline).foregroundStyle(.secondary)
            Button("New Skill") { showNewSkillSheet = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            ForEach(groupedCategories.keys.sorted(), id: \.self) { category in
                Section(category) {
                    ForEach(groupedCategories[category] ?? []) { skill in
                        HStack {
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
                                }
                            }
                            .buttonStyle(.plain)

                            Toggle("", isOn: Binding(
                                get: { skill.enabled ?? true },
                                set: { newValue in
                                    Task { await toggleSkill(skill.name, enabled: newValue) }
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                skillToDelete = skill
                                showDeleteAlert = true
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadSkills() }
    }

    private var groupedCategories: [String: [HermesGatewayClient.SkillDTO]] {
        Dictionary(grouping: skills, by: { $0.category ?? "Uncategorized" })
    }

    private func loadSkills() async {
        guard let active = store.activeEndpoint else {
            errorMessage = "No server configured."
            debugInfo = nil
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        debugInfo = nil
        do {
            // Using WebFetchClient to bypass ATS for HTTP endpoints
            let result = try await WebFetchClient.shared.fetchJSON(
                HermesGatewayClient.SkillsDTO.self,
                baseURL: active.url,
                path: "/api/skills"
            )
            skills = result.skills
        } catch {
            errorMessage = error.localizedDescription
            debugInfo = HermesGatewayClient.RequestDebug(
                method: "GET",
                url: "WebFetch: \(active.url.absoluteString)/api/skills",
                note: "WebFetch failed",
                errorDomain: (error as NSError).domain,
                errorCode: (error as NSError).code,
                errorDescription: error.localizedDescription
            )
        }
        isLoading = false
    }

    private func toggleSkill(_ name: String, enabled: Bool) async {
        guard let active = store.activeEndpoint else { return }
        _ = try? await HermesGatewayClient.shared.toggleSkill(baseURL: active.url, name: name, enabled: enabled)
        await loadSkills()
    }

    private func deleteSkill(_ name: String) async {
        guard let active = store.activeEndpoint else { return }
        _ = try? await HermesGatewayClient.shared.deleteSkill(baseURL: active.url, name: name)
        await loadSkills()
    }
}

struct SkillDetailView: View {
    let store: EndpointStore
    let skill: HermesGatewayClient.SkillDTO
    let onRefresh: (() -> Void)?
    @State private var content: String?
    @State private var isLoading = true
    @State private var editContent = ""
    @State private var isEditing = false
    @State private var saveStatus: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if isEditing {
                    VStack(spacing: 8) {
                        TextEditor(text: $editContent)
                            .font(.body)
                            .frame(minHeight: 300)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
                            .padding()

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                isEditing = false
                            }
                            .buttonStyle(.bordered)

                            Button("Save") {
                                Task { await saveContent() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(saveStatus == "Saving…")
                        }
                        .padding(.bottom)

                        if let saveStatus {
                            Text(saveStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isEditing {
                        Button("Edit") {
                            editContent = content ?? ""
                            isEditing = true
                        }
                    }
                }
            }
        }
        .task {
            guard let active = store.activeEndpoint else { return }
            do {
                let result = try await HermesGatewayClient.shared.fetchSkillContent(baseURL: active.url, name: skill.name)
                content = result.content ?? result.description
                editContent = content ?? ""
            } catch {
                content = "Failed to load content."
            }
            isLoading = false
        }
    }

    private func saveContent() async {
        guard let active = store.activeEndpoint else { return }
        saveStatus = "Saving…"

        do {
            let ok = try await HermesGatewayClient.shared.saveSkill(
                baseURL: active.url,
                name: skill.name,
                content: editContent
            )
            if ok {
                content = editContent
                isEditing = false
                saveStatus = nil
                onRefresh?()
            } else {
                saveStatus = "Failed to save"
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }

        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); saveStatus = nil }
    }
}
