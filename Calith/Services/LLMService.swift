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

/// Top-level base prompt shared by all providers.
/// Computed so the current date/time is always fresh for each request.
var basePrompt: [String] {
    let dateString = Date.now.formatted(date: .complete, time: .shortened)
    return [
        "You are Calith, a helpful personal assistant. Be concise and direct.",
        "The current date and time is \(dateString).",
        "You have access to tools for file operations, shell commands, AppleScript, web fetching, and web search.",
        "Use tools when the user asks you to interact with their filesystem, run commands, fetch web pages, or search the web.",
        "You can chain multiple tool calls in a single response. For example, search the web to find a URL, then fetch that URL for detailed content.",
        "When the user asks about local businesses, events, weather, or services, incorporate their location into your search queries for more relevant results.",
        "If you are unsure about something, use your tools to look it up rather than guessing. Never fabricate URLs, facts, or data.",
        "When searching for time-sensitive information (events, showtimes, schedules, news), always consider the current date. Do not assume information is unavailable based on outdated dates in search results.",
        "Your responses are rendered as Markdown. Use formatting (headers, lists, bold) when it improves readability, but keep it minimal for short answers.",
    ]
}

/// Events streamed from an LLM backend during response generation.
enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case toolCall(id: String, name: String, arguments: String)
    case done
    case error(Error)
}

/// A tool definition passed to the LLM backend.
struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parametersSchema: String // JSON Schema as a string
}

/// Common interface for LLM backends (Foundation Models, OpenAI).
protocol LLMService: Sendable {
    /// Sends a user message (with conversation history, attachments, and tool results) and streams back events.
    func sendMessage(
        _ text: String,
        attachments: [Attachment],
        history: [Message],
        memories: [Memory],
        location: String?,
        tools: [ToolDefinition],
        toolResults: [ToolResult]
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Clears any backend-specific conversation state.
    func clearConversation() async
}

/// The result of executing a tool, to be fed back to the LLM.
struct ToolResult: Sendable {
    let toolCallID: String
    let toolName: String
    let output: String
}
