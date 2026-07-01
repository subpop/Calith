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

import Foundation
import SwiftData
import Observation
import os

/// Represents an external LLM provider. An empty/nil value means Apple Intelligence (on-device).
enum LLMProvider: String, CaseIterable, Sendable {
    case openAI = "openai"
    case claude = "claude"
    case gemini = "gemini"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        }
    }

    var iconName: String {
        switch self {
        case .openAI: "openai"
        case .claude: "anthropic"
        case .gemini: "gemini"
        case .ollama: "ollama"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .claude: "https://api.anthropic.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .ollama: "http://localhost:11434"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o"
        case .claude: "claude-sonnet-4-20250514"
        case .gemini: "gemini-2.5-flash"
        case .ollama: "llama3.1"
        }
    }

    var subtitle: String {
        switch self {
        case .openAI: "OpenAI"
        case .claude: "Anthropic"
        case .gemini: "Google"
        case .ollama: "Local"
        }
    }

    /// Whether this provider requires an API key (Ollama typically does not).
    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .claude, .gemini: true
        case .ollama: false
        }
    }

    /// Describes what the Context setting controls for this provider.
    var contextDescription: String {
        switch self {
        case .openAI: "Controls when OpenAI compacts the conversation to stay within the token budget."
        case .claude: "Sets the maximum number of tokens Anthropic may generate per response."
        case .gemini: "Sets the maximum number of tokens Google may generate per response."
        case .ollama: "Sets the context window size (num_ctx). Ollama defaults to 2048 when not specified."
        }
    }

    // MARK: - UserDefaults keys

    var apiKeyKey: String { "\(rawValue).apiKey" }
    var baseURLKey: String { "\(rawValue).baseURL" }
    var modelKey: String { "\(rawValue).model" }
    var contextSizeKey: String { "\(rawValue).contextSize" }
}

/// Discrete context window sizes for third-party providers.
enum ContextSize: String, CaseIterable, Sendable {
    case verySmall = "verySmall"
    case small = "small"
    case medium = "medium"
    case large = "large"
    case veryLarge = "veryLarge"

    var displayName: String {
        switch self {
        case .verySmall: "Very Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .veryLarge: "Very Large"
        }
    }

    var tokenLimit: Int {
        switch self {
        case .verySmall: 4_096
        case .small: 16_384
        case .medium: 64_000
        case .large: 128_000
        case .veryLarge: 200_000
        }
    }
}

@Observable
final class ConversationViewModel {
    var isResponding = false
    private(set) var streamingBuffer = MarkdownBuffer()
    private(set) var thinkingBuffer = MarkdownBuffer()

    var streamingContent: String { streamingBuffer.content }
    var streamingBlocks: [String] { streamingBuffer.blocks }
    var streamingPending: String { streamingBuffer.pending }
    var isStreamingEmpty: Bool { streamingBuffer.isEmpty }
    var streamingCharacterCount: Int { streamingBuffer.characterCount }

    var thinkingContent: String { thinkingBuffer.content }
    var thinkingBlocks: [String] { thinkingBuffer.blocks }
    var thinkingPending: String { thinkingBuffer.pending }
    var isThinkingEmpty: Bool { thinkingBuffer.isEmpty }
    var thinkingCharacterCount: Int { thinkingBuffer.characterCount }

    /// The active provider, read from UserDefaults. Nil means Apple Intelligence.
    var activeProvider: LLMProvider? {
        guard let raw = UserDefaults.standard.string(forKey: "activeProvider"),
              !raw.isEmpty
        else { return nil }
        return LLMProvider(rawValue: raw)
    }

    // MARK: - Conversation State

    /// The conversation currently being viewed. Nil means a fresh "New Conversation" that
    /// hasn't been persisted yet (lazy creation on first send).
    var currentConversation: Conversation?

    /// Messages for the current conversation, sorted by timestamp.
    var messages: [Message] {
        guard let conversation = currentConversation else { return [] }
        return conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    let toolExecutor = ToolExecutor()
    let locationService = LocationService()
    private let memoryService = MemoryService()
    private let embeddingService = EmbeddingService()

    private let foundationModelService = FoundationModelService()
    private let openAIService = OpenAIService()
    private let anthropicService = AnthropicService()
    private let geminiService = GeminiService()
    private let ollamaService = OllamaService()
    private var streamTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    private var lastUserMessage = ""
    private var lastLocation: String?

    /// Continuation used to resume after a tool confirmation decision.
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    private var currentService: any LLMService {
        switch activeProvider {
        case nil:     return foundationModelService
        case .openAI: return openAIService
        case .claude: return anthropicService
        case .gemini: return geminiService
        case .ollama: return ollamaService
        }
    }

    init() {
        foundationModelService.setTools(toolExecutor.foundationModelTools)
        syncProviderSettings()
    }

    /// Reads the active provider's settings from UserDefaults and configures the service.
    func syncProviderSettings() {
        guard let provider = activeProvider else { return }
        let defaults = UserDefaults.standard
        let apiKey = defaults.string(forKey: provider.apiKeyKey) ?? ""
        let baseURL = defaults.string(forKey: provider.baseURLKey) ?? provider.defaultBaseURL
        let model = defaults.string(forKey: provider.modelKey) ?? provider.defaultModel
        let contextTokenLimit = defaults.string(forKey: provider.contextSizeKey)
            .flatMap { ContextSize(rawValue: $0) }?.tokenLimit

        switch provider {
        case .openAI:
            openAIService.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                requiresAPIKey: true, contextTokenLimit: contextTokenLimit
            )
        case .claude:
            anthropicService.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                maxOutputTokens: contextTokenLimit ?? 8192
            )
        case .gemini:
            geminiService.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                maxOutputTokens: contextTokenLimit ?? 8192
            )
        case .ollama:
            ollamaService.configure(
                baseURL: baseURL, model: model,
                contextWindowSize: contextTokenLimit
            )
        }
    }

    func send(_ text: String, attachments: [Attachment] = [], context: ModelContext) {
        guard !isResponding else { return }

        // Create a conversation if this is the first message
        let conversation: Conversation
        if let existing = currentConversation {
            conversation = existing
        } else {
            conversation = Conversation()
            context.insert(conversation)
            currentConversation = conversation
        }

        // Insert attachments into the context
        for attachment in attachments {
            context.insert(attachment)
        }

        // Insert user message with attachments
        let userMessage = Message(role: "user", content: text, attachments: attachments)
        userMessage.conversation = conversation
        context.insert(userMessage)
        conversation.updatedAt = .now
        try? context.save()

        // Fetch all memories for semantic retrieval
        let memoryDescriptor = FetchDescriptor<Memory>(sortBy: [SortDescriptor(\.createdAt)])
        let allMemories = (try? context.fetch(memoryDescriptor)) ?? []

        // Check if this is the first user message (for auto-titling later)
        let isFirstMessage = conversation.title == "New Conversation"

        // Start streaming
        isResponding = true
        streamingBuffer.reset()
        thinkingBuffer.reset()
        lastUserMessage = text

        // Sync provider settings in case they changed
        if activeProvider != nil {
            syncProviderSettings()
        }

        let toolDefs = toolExecutor.openAIToolDefinitions
        let locationEnabled = UserDefaults.standard.bool(forKey: "locationEnabled")

        streamTask = Task { [weak self] in
            guard let self else { return }

            // Fetch location if enabled
            self.lastLocation = locationEnabled
                ? await self.locationService.currentLocationDescription()
                : nil

            let relevantMemories = self.embeddingService.topK(
                query: text, among: allMemories, k: 15
            )

            let stream = self.currentService.sendMessage(
                text,
                attachments: attachments,
                history: [],
                memories: relevantMemories,
                location: self.lastLocation,
                tools: toolDefs,
                toolResults: []
            )

            await self.consumeStream(
                stream,
                conversation: conversation,
                context: context,
                memories: allMemories
            )

            // Auto-title the conversation after the first exchange completes
            if isFirstMessage && conversation.title == "New Conversation" {
                self.generateTitle(
                    for: conversation,
                    firstMessage: text,
                    context: context
                )
            }

            self.isResponding = false
            self.streamingBuffer.reset()
            self.thinkingBuffer.reset()
        }
    }

    // MARK: - Tool Call Handling

    private func handleToolCall(
        id: String, name: String, arguments: String,
        context: ModelContext, memories: [Memory]
    ) async {
        // Check if confirmation is required
        if toolExecutor.requiresConfirmation(name) {
            // Show confirmation card and wait for user decision
            toolExecutor.pendingConfirmation = ToolExecutor.PendingToolCall(
                id: id, name: name, arguments: arguments
            )

            let approved = await withCheckedContinuation { continuation in
                self.confirmationContinuation = continuation
            }

            toolExecutor.pendingConfirmation = nil

            guard approved else {
                // User denied — insert a message and send denial back
                let deniedMsg = Message(
                    role: "tool",
                    content: "Tool call denied by user.",
                    toolCallID: id,
                    toolName: name
                )
                deniedMsg.conversation = currentConversation
                context.insert(deniedMsg)
                try? context.save()

                // Send denial result back to the LLM
                let result = ToolResult(toolCallID: id, toolName: name, output: "User denied this tool call.")
                await sendToolResults([result], context: context, memories: memories)
                return
            }
        }

        // Execute the tool
        let toolMsg = Message(
            role: "tool",
            content: "Running \(name)...",
            toolCallID: id,
            toolName: name,
            toolArguments: arguments,
            isToolConfirmationPending: false
        )
        toolMsg.conversation = currentConversation
        context.insert(toolMsg)
        try? context.save()

        let output = await toolExecutor.execute(name: name, arguments: arguments)

        // Update message with result
        toolMsg.content = output
        try? context.save()

        // Send result back to the LLM for a follow-up response
        let result = ToolResult(toolCallID: id, toolName: name, output: output)
        await sendToolResults([result], context: context, memories: memories)
    }

    /// Consumes a coalesced stream, applying batched buffer updates.
    ///
    /// Uses `coalescedEvents(from:)` to merge consecutive text/thinking deltas
    /// off the main actor, so this `@MainActor` method receives fewer, larger
    /// updates — reducing per-token rendering overhead.
    private func consumeStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        conversation: Conversation?,
        context: ModelContext,
        memories: [Memory]
    ) async {
        do {
            for try await event in coalescedEvents(from: stream) {
                switch event {
                case .textDelta(let delta):
                    self.streamingBuffer.append(delta)

                case .thinkingDelta(let delta):
                    self.thinkingBuffer.append(delta)

                case .toolCall(let id, let name, let arguments):
                    await self.handleToolCall(
                        id: id, name: name, arguments: arguments,
                        context: context, memories: memories
                    )

                case .done:
                    self.streamingBuffer.flush()
                    self.thinkingBuffer.flush()
                    if !self.streamingBuffer.isEmpty {
                        let content = self.streamingBuffer.content
                        let thinking = self.thinkingBuffer.isEmpty ? nil : self.thinkingBuffer.content
                        let msg = Message(
                            role: "assistant",
                            content: content,
                            thinkingContent: thinking
                        )
                        msg.conversation = conversation
                        context.insert(msg)
                        conversation?.updatedAt = .now
                        try? context.save()

                        self.memoryService.extractMemories(
                            userMessage: self.lastUserMessage,
                            assistantResponse: content,
                            context: context
                        )
                    }

                case .error(let error):
                    let msg = Message(
                        role: "assistant",
                        content: "Error: \(error.localizedDescription)"
                    )
                    msg.conversation = conversation
                    context.insert(msg)
                    try? context.save()
                }
            }
        } catch {
            let msg = Message(
                role: "assistant",
                content: "Error: \(error.localizedDescription)"
            )
            msg.conversation = conversation
            context.insert(msg)
            try? context.save()
        }
    }

    private func sendToolResults(_ results: [ToolResult], context: ModelContext, memories: [Memory]) async {
        let toolDefs = toolExecutor.openAIToolDefinitions
        streamingBuffer.reset()
        thinkingBuffer.reset()

        let relevantMemories = self.embeddingService.topK(
            query: self.lastUserMessage, among: memories, k: 15
        )

        let stream = currentService.sendMessage(
            "",
            attachments: [],
            history: [],
            memories: relevantMemories,
            location: lastLocation,
            tools: toolDefs,
            toolResults: results
        )

        await consumeStream(
            stream,
            conversation: currentConversation,
            context: context,
            memories: memories
        )

        streamingBuffer.reset()
        thinkingBuffer.reset()
    }

    func cancel(context: ModelContext) {
        streamTask?.cancel()
        streamTask = nil

        if !streamingBuffer.isEmpty {
            let message = Message(role: "assistant", content: streamingBuffer.content)
            message.conversation = currentConversation
            context.insert(message)
            try? context.save()
        }

        isResponding = false
        streamingBuffer.reset()
        thinkingBuffer.reset()
    }

    // MARK: - Confirmation Response

    func approveToolCall() {
        confirmationContinuation?.resume(returning: true)
        confirmationContinuation = nil
    }

    func denyToolCall() {
        confirmationContinuation?.resume(returning: false)
        confirmationContinuation = nil
    }

    // MARK: - Conversation Management

    /// Starts a fresh conversation, cancelling any in-progress stream.
    func newConversation(context: ModelContext) async {
        streamTask?.cancel()
        streamTask = nil
        titleTask?.cancel()
        titleTask = nil

        await currentService.clearConversation()
        currentConversation = nil
        isResponding = false
        streamingBuffer.reset()
        thinkingBuffer.reset()
    }

    /// Switches to an existing conversation.
    func switchConversation(to conversation: Conversation, context: ModelContext) async {
        streamTask?.cancel()
        streamTask = nil
        titleTask?.cancel()
        titleTask = nil

        await currentService.clearConversation()
        currentConversation = conversation
        isResponding = false
        streamingBuffer.reset()
        thinkingBuffer.reset()
    }

    /// Deletes a conversation and its messages from the database.
    func deleteConversation(_ conversation: Conversation, context: ModelContext) {
        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
        context.delete(conversation)
        try? context.save()
    }

    // MARK: - Auto Title Generation

    /// Creates a fresh, disposable LLM service instance for one-shot requests
    /// (like title generation) that won't pollute the main conversation state.
    private func makeOneShotService() -> any LLMService {
        guard let provider = activeProvider else {
            let service = FoundationModelService()
            return service
        }

        let defaults = UserDefaults.standard
        let apiKey = defaults.string(forKey: provider.apiKeyKey) ?? ""
        let baseURL = defaults.string(forKey: provider.baseURLKey) ?? provider.defaultBaseURL
        let model = defaults.string(forKey: provider.modelKey) ?? provider.defaultModel
        let contextTokenLimit = defaults.string(forKey: provider.contextSizeKey)
            .flatMap { ContextSize(rawValue: $0) }?.tokenLimit

        switch provider {
        case .openAI:
            let service = OpenAIService()
            service.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                requiresAPIKey: true, contextTokenLimit: contextTokenLimit
            )
            return service
        case .claude:
            let service = AnthropicService()
            service.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                maxOutputTokens: contextTokenLimit ?? 8192
            )
            return service
        case .gemini:
            let service = GeminiService()
            service.configure(
                apiKey: apiKey, baseURL: baseURL, model: model,
                maxOutputTokens: contextTokenLimit ?? 8192
            )
            return service
        case .ollama:
            let service = OllamaService()
            service.configure(
                baseURL: baseURL, model: model,
                contextWindowSize: contextTokenLimit
            )
            return service
        }
    }

    /// Generates a short title for the conversation using the configured LLM.
    private func generateTitle(for conversation: Conversation, firstMessage: String, context: ModelContext) {
        titleTask?.cancel()
        titleTask = Task { [weak self] in
            guard let self else { return }
            let prompt = "Generate a brief title (3-7 words) for a conversation that starts with the following message. Reply with only the title text, no quotes or punctuation at the end.\n\nMessage: \(firstMessage)"

            let service = self.makeOneShotService()
            var title = ""
            let stream = service.sendMessage(
                prompt,
                attachments: [],
                history: [],
                memories: [],
                location: nil,
                tools: [],
                toolResults: []
            )

            do {
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        title += delta
                    case .done:
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            conversation.title = trimmed
                            try? context.save()
                        }
                    default:
                        break
                    }
                }
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calith", category: "TitleGeneration")
                    .error("Title generation failed: \(error)")
            }
        }
    }

}

// MARK: - Stream Coalescing

/// Wraps a raw stream of `StreamEvent` values, merging consecutive text and
/// thinking deltas into single coalesced events.
///
/// The production task runs on the cooperative thread pool (not the main actor),
/// so it can consume network tokens as fast as they arrive without blocking
/// rendering. The consumer (on `@MainActor`) receives fewer, larger batches —
/// naturally throttled by main-actor availability.
nonisolated private func coalescedEvents(
    from source: AsyncThrowingStream<StreamEvent, Error>
) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task.detached {
            // Minimum interval between yielded delta batches (~2 display frames).
            let coalesceInterval: ContinuousClock.Duration = .milliseconds(32)
            var textBatch = ""
            var thinkingBatch = ""
            var lastYield: ContinuousClock.Instant = .now

            func flushText() {
                if !textBatch.isEmpty {
                    continuation.yield(.textDelta(textBatch))
                    textBatch = ""
                    lastYield = .now
                }
            }

            func flushThinking() {
                if !thinkingBatch.isEmpty {
                    continuation.yield(.thinkingDelta(thinkingBatch))
                    thinkingBatch = ""
                    lastYield = .now
                }
            }

            func flushIfReady() {
                guard ContinuousClock.now - lastYield >= coalesceInterval else { return }
                flushText()
                flushThinking()
            }

            do {
                for try await event in source {
                    switch event {
                    case .textDelta(let delta):
                        flushThinking()
                        textBatch += delta
                        flushIfReady()

                    case .thinkingDelta(let delta):
                        flushText()
                        thinkingBatch += delta
                        flushIfReady()

                    case .toolCall, .done, .error:
                        flushText()
                        flushThinking()
                        continuation.yield(event)
                    }
                }
                flushText()
                flushThinking()
                continuation.finish()
            } catch {
                flushText()
                flushThinking()
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
