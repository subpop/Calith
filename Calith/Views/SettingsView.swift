// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import SwiftData
import CoreLocation

struct SettingsView: View {
    @ObservedObject var updater: SoftwareUpdater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(updater: updater)
            }

            Tab("Tools", systemImage: "wrench") {
                ToolSettingsTab()
            }

            Tab("Memories", systemImage: "brain") {
                MemoriesSettingsTab()
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Provider Icon

/// Returns an `Image` whose underlying `NSImage` is sized to `size` points
/// so that macOS `Picker` renders it at the same scale as an SF Symbol.
private func providerIcon(_ name: String, size: CGFloat = 16) -> Image {
    guard let original = NSImage(named: name) else {
        return Image(name)
    }
    let resized = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        original.draw(in: rect)
        return true
    }
    resized.isTemplate = original.isTemplate
    return Image(nsImage: resized)
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @ObservedObject var updater: SoftwareUpdater
    @AppStorage("activeProvider") private var activeProviderRaw = ""
    @AppStorage("locationEnabled") private var locationEnabled = false
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var locationService = LocationService()

    private var selectedProvider: Binding<LLMProvider?> {
        Binding(
            get: {
                guard !activeProviderRaw.isEmpty else { return nil }
                return LLMProvider(rawValue: activeProviderRaw)
            },
            set: { newValue in
                activeProviderRaw = newValue?.rawValue ?? ""
            }
        )
    }

    private var providerDescription: String {
        guard let provider = selectedProvider.wrappedValue else {
            return "Using the on-device Foundation model. Private and requires no configuration."
        }
        return "Requests are sent to the \(provider.displayName) API."
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if let provider = selectedProvider.wrappedValue {
                            providerIcon(provider.iconName, size: 24)
                        } else {
                            Image(systemName: "apple.intelligence")
                                .font(.title)
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading) {
                        Text(selectedProvider.wrappedValue?.displayName ?? "Apple Intelligence")
                            .font(.headline)
                        Text(providerDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Provider", selection: selectedProvider) {
                    Label {
                        Text("Apple Intelligence")
                    } icon: {
                        Image(systemName: "apple.intelligence")
                    }
                        .tag(nil as LLMProvider?)
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Label {
                            Text(provider.displayName)
                        } icon: {
                            providerIcon(provider.iconName)
                        }
                        .tag(provider as LLMProvider?)
                    }
                }
            } header: {
                Text("Third Party Providers")
            } footer: {
                Text("Use a third-party provider to expand reasoning and context. Your data will be sent to the provider's servers. Token rates may apply.")
            }

            if let provider = selectedProvider.wrappedValue {
                ProviderConfigSection(provider: provider)
            }

            Section {
                Toggle("Share Location", isOn: $locationEnabled)
                    .onChange(of: locationEnabled) {
                        if locationEnabled {
                            locationService.requestPermissionAndPrefetch()
                        }
                    }
            } header: {
                Text("Location")
            } footer: {
                Text("When enabled, your approximate location is included in the system prompt to provide relevant context.")
            }

            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    )
                )
            } header: {
                Text("Updates")
            }

            Section {
                Button("Reset Calith", role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Delete all messages, memories, and configuration.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("Reset Calith?", isPresented: $showResetConfirmation) {
            Button("Reset Everything", role: .destructive) {
                performReset()
            }
        } message: {
            Text("This will delete all messages, memories, and settings. This cannot be undone.")
        }
    }

    private func performReset() {
        let messageDescriptor = FetchDescriptor<Message>()
        if let messages = try? modelContext.fetch(messageDescriptor) {
            for message in messages {
                modelContext.delete(message)
            }
        }

        let memoryDescriptor = FetchDescriptor<Memory>()
        if let memories = try? modelContext.fetch(memoryDescriptor) {
            for memory in memories {
                modelContext.delete(memory)
            }
        }

        try? modelContext.save()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeProvider")
        defaults.removeObject(forKey: "locationEnabled")
        for provider in LLMProvider.allCases {
            KeychainHelper.shared.delete(forKey: provider.apiKeyKey)
            defaults.removeObject(forKey: provider.baseURLKey)
            defaults.removeObject(forKey: provider.modelKey)
            defaults.removeObject(forKey: provider.contextSizeKey)
        }
    }
}

// MARK: - Provider Configuration Section

private struct ProviderConfigSection: View {
    let provider: LLMProvider

    @State private var apiKey = ""
    @AppStorage private var baseURL: String?
    @AppStorage private var model: String?
    @AppStorage private var contextSizeRaw: String?

    init(provider: LLMProvider) {
        self.provider = provider
        _apiKey = State(initialValue: KeychainHelper.shared.read(forKey: provider.apiKeyKey) ?? "")
        _baseURL = AppStorage(provider.baseURLKey)
        _model = AppStorage(provider.modelKey)
        _contextSizeRaw = AppStorage(provider.contextSizeKey)
    }

    private var baseURLBinding: Binding<String> {
        Binding(get: { baseURL ?? "" }, set: { baseURL = $0.isEmpty ? nil : $0 })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { model ?? "" }, set: { model = $0.isEmpty ? nil : $0 })
    }

    private var selectedContextSize: Binding<ContextSize?> {
        Binding(
            get: {
                guard let raw = contextSizeRaw else { return nil }
                return ContextSize(rawValue: raw)
            },
            set: { newValue in
                contextSizeRaw = newValue?.rawValue
            }
        )
    }

    var body: some View {
        Section {
            if provider.requiresAPIKey {
                SecureField(text: $apiKey, prompt: Text("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}").monospaced()) {
                    Text("API Key")
                        .font(.body)
                }
                .font(.system(.body, design: .monospaced))
                .onChange(of: apiKey) { _, newValue in
                    if newValue.isEmpty {
                        KeychainHelper.shared.delete(forKey: provider.apiKeyKey)
                    } else {
                        KeychainHelper.shared.save(newValue, forKey: provider.apiKeyKey)
                    }
                }
            }
            TextField("Base URL", text: baseURLBinding, prompt: Text(provider.defaultBaseURL))
            ModelPickerField(
                    provider: provider,
                    selectedModel: modelBinding,
                    apiKey: apiKey,
                    baseURL: baseURL ?? provider.defaultBaseURL
                )
            Picker("Context", selection: selectedContextSize) {
                Text("Default").tag(nil as ContextSize?)
                ForEach(ContextSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size as ContextSize?)
                }
            }
        } header: {
            Text("Configuration")
        } footer: {
            Text(provider.contextDescription)
        }
    }
}

// MARK: - Model Picker

private struct ModelPickerField: View {
    let provider: LLMProvider
    @Binding var selectedModel: String
    let apiKey: String
    let baseURL: String

    @State private var models: [ModelLookupService.ModelInfo] = []
    @State private var isLoading = false

    private let lookupService = ModelLookupService()

    var body: some View {
        HStack {
            Picker("Model", selection: $selectedModel) {
                // Include the current selection if it's not in the fetched list.
                if !selectedModel.isEmpty, !models.contains(where: { $0.id == selectedModel }) {
                    Text(selectedModel).tag(selectedModel)
                }
                ForEach(models) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: TaskID(provider: provider, apiKey: apiKey, baseURL: baseURL)) {
            await loadModels()
        }
    }

    private struct TaskID: Equatable {
        let provider: LLMProvider
        let apiKey: String
        let baseURL: String
    }

    private func loadModels() async {
        guard !provider.requiresAPIKey || !apiKey.isEmpty else {
            models = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await lookupService.fetchModels(
                for: provider,
                apiKey: apiKey,
                baseURL: baseURL
            )
            models = fetched

            // If nothing is selected yet, pick the default.
            if selectedModel.isEmpty, !fetched.isEmpty {
                selectedModel = provider.defaultModel
            }
        } catch {
            models = []
        }
    }
}

// MARK: - Tool Settings

struct ToolSettingsTab: View {
    @AppStorage("tool.ReadFile") private var readFilePolicy = "Always Run"
    @AppStorage("tool.WriteFile") private var writeFilePolicy = "Always Run"
    @AppStorage("tool.RunCommand") private var runCommandPolicy = "Always Ask"
    @AppStorage("tool.ListDirectory") private var listDirectoryPolicy = "Always Run"
    @AppStorage("tool.RunAppleScript") private var runAppleScriptPolicy = "Always Ask"
    @AppStorage("tool.WebFetch") private var webFetchPolicy = "Always Run"
    @AppStorage("tool.WebSearch") private var webSearchPolicy = "Always Run"

    private let policyOptions = ["Always Run", "Always Ask"]

    var body: some View {
        Form {
            Section("Tool Confirmation Policies") {
                Picker("Read File", selection: $readFilePolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("Write File", selection: $writeFilePolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("Run Command", selection: $runCommandPolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("List Directory", selection: $listDirectoryPolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("Run AppleScript", selection: $runAppleScriptPolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("Web Fetch", selection: $webFetchPolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
                Picker("Web Search", selection: $webSearchPolicy) {
                    ForEach(policyOptions, id: \.self) { Text($0) }
                }
            }

            Section {
                Text("\"Always Ask\" tools will show a confirmation card before running. \"Always Run\" tools execute immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Memories Settings

struct MemoriesSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var memories: [Memory]

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if memories.isEmpty {
                ContentUnavailableView(
                    "No Memories",
                    systemImage: "brain",
                    description: Text("Calith will learn about you as you chat.")
                )
            } else {
                List {
                    ForEach(memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.fact)
                            HStack {
                                Text(memory.category)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.fill.tertiary, in: Capsule())
                                Text(memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteMemories)
                }

                Divider()
                
                HStack {
                    Text("\(memories.count) memories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete All", role: .destructive) {
                        for memory in memories {
                            modelContext.delete(memory)
                        }
                        try? modelContext.save()
                    }
                    .disabled(memories.isEmpty)
                }
                .padding()
            }

        }
    }

    private func deleteMemories(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(memories[index])
        }
        try? modelContext.save()
    }
}

// MARK: Previews

#Preview("General Settings") {
    GeneralSettingsTab(updater: SoftwareUpdater())
        .modelContainer(for: [Message.self, Memory.self], inMemory: true)
}

#Preview("Tool Settings") {
    ToolSettingsTab()
        .modelContainer(for: [Message.self, Memory.self], inMemory: true)
}

#Preview("Memories Settings - Empty") {
    MemoriesSettingsTab()
        .modelContainer(for: Memory.self, inMemory: true)
}

#Preview("Memories Settings - Populated") {
    let container: ModelContainer = {
        let container = try! ModelContainer(for: Memory.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(Memory(
            fact: "User prefers dark mode for all development environments",
            category: "preference",
            createdAt: Date(timeIntervalSinceNow: -86400 * 7),
            source: "conversation"
        ))
        context.insert(Memory(
            fact: "User is a senior iOS developer working on personal projects",
            category: "background",
            createdAt: Date(timeIntervalSinceNow: -86400 * 3),
            source: "conversation"
        ))
        context.insert(Memory(
            fact: "Prefers SwiftUI over UIKit whenever possible",
            category: "preference",
            createdAt: Date(timeIntervalSinceNow: -3600),
            source: "conversation"
        ))
        try! context.save()
        return container
    }()

    MemoriesSettingsTab()
        .modelContainer(container)
}

