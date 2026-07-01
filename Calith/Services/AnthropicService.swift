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

final class AnthropicService: LLMService, @unchecked Sendable {
    private var conversationMessages: [[String: Any]] = []
    private var apiKey: String = ""
    private var baseURL: String = "https://api.anthropic.com/v1"
    private var model: String = "claude-sonnet-4-20250514"
    /// Maximum number of tokens the model may generate in a single response.
    /// Anthropic requires this field. The context window is fixed per model.
    private var maxOutputTokens: Int = 8192

    func configure(apiKey: String, baseURL: String, model: String, maxOutputTokens: Int = 8192) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
    }

    // MARK: - Request building

    private func buildSystemPrompt(memories: [Memory], location: String?) -> String {
        var parts = basePrompt

        if !memories.isEmpty {
            let facts = memories.map { "- \($0.fact)" }.joined(separator: "\n")
            parts.append("Known facts about the user:\n\(facts)")
        }

        if let location {
            parts.append("The user's current location is \(location).")
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildToolDefinitions(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let paramsData = tool.parametersSchema.data(using: .utf8),
                  let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
            else { return nil }

            return [
                "name": tool.name,
                "description": tool.description,
                "input_schema": params,
            ] as [String: Any]
        }
    }

    private func buildMessages(
        _ text: String,
        attachments: [Attachment],
        toolResults: [ToolResult]
    ) -> [[String: Any]] {
        var messages = conversationMessages

        if !toolResults.isEmpty {
            // Tool results are sent as a user message with tool_result content blocks.
            let resultBlocks: [[String: Any]] = toolResults.map { result in
                [
                    "type": "tool_result",
                    "tool_use_id": result.toolCallID,
                    "content": result.output,
                ]
            }
            messages.append([
                "role": "user",
                "content": resultBlocks,
            ])
        } else if attachments.isEmpty {
            messages.append([
                "role": "user",
                "content": text,
            ])
        } else {
            // Multi-modal: build content blocks with attachments + text
            var content: [[String: Any]] = []

            for attachment in attachments {
                let base64 = attachment.data.base64EncodedString()

                if attachment.isImage {
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": attachment.mimeType,
                            "data": base64,
                        ] as [String: Any],
                    ])
                } else if attachment.isPDF {
                    content.append([
                        "type": "document",
                        "source": [
                            "type": "base64",
                            "media_type": attachment.mimeType,
                            "data": base64,
                        ] as [String: Any],
                    ])
                } else if attachment.isText, let textContent = String(data: attachment.data, encoding: .utf8) {
                    content.append([
                        "type": "text",
                        "text": "[\(attachment.filename)]:\n\(textContent)",
                    ])
                }
            }

            if !text.isEmpty {
                content.append([
                    "type": "text",
                    "text": text,
                ])
            }

            messages.append([
                "role": "user",
                "content": content,
            ])
        }

        return messages
    }

    // MARK: - LLMService

    func sendMessage(
        _ text: String,
        attachments: [Attachment],
        history: [Message],
        memories: [Memory],
        location: String?,
        tools: [ToolDefinition],
        toolResults: [ToolResult]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else {
                        throw AnthropicError.missingAPIKey
                    }

                    let messages = buildMessages(text, attachments: attachments, toolResults: toolResults)
                    let systemPrompt = buildSystemPrompt(memories: memories, location: location)
                    let toolDefs = buildToolDefinitions(tools)

                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": maxOutputTokens,
                        "system": systemPrompt,
                        "messages": messages,
                        "stream": true,
                        "thinking": ["type": "adaptive"],
                    ]

                    if !toolDefs.isEmpty {
                        body["tools"] = toolDefs
                    }

                    let bodyData = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
                    request.httpMethod = "POST"
                    request.httpBody = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw AnthropicError.httpError(statusCode: statusCode)
                    }

                    // Parse SSE stream
                    // Track tool use blocks being built across events.
                    var activeToolBlocks: [Int: (id: String, name: String, jsonAccumulator: String)] = [:]
                    var activeThinkingBlocks: Set<Int> = []
                    var thinkingAccumulators: [Int: String] = [:]
                    var thinkingSignatures: [Int: String] = [:]
                    var assistantContentBlocks: [[String: Any]] = []
                    var textAccumulator = ""

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard let data = jsonString.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String
                        else { continue }

                        switch type {
                        case "content_block_start":
                            if let index = event["index"] as? Int,
                               let block = event["content_block"] as? [String: Any],
                               let blockType = block["type"] as? String
                            {
                                if blockType == "tool_use",
                                   let id = block["id"] as? String,
                                   let name = block["name"] as? String
                                {
                                    activeToolBlocks[index] = (id: id, name: name, jsonAccumulator: "")
                                } else if blockType == "thinking" {
                                    activeThinkingBlocks.insert(index)
                                    thinkingAccumulators[index] = ""
                                }
                            }

                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               let deltaType = delta["type"] as? String
                            {
                                if deltaType == "text_delta",
                                   let text = delta["text"] as? String
                                {
                                    textAccumulator += text
                                    continuation.yield(.textDelta(text))
                                } else if deltaType == "thinking_delta",
                                          let index = event["index"] as? Int,
                                          let thinking = delta["thinking"] as? String
                                {
                                    thinkingAccumulators[index, default: ""] += thinking
                                    continuation.yield(.thinkingDelta(thinking))
                                } else if deltaType == "signature_delta",
                                          let index = event["index"] as? Int,
                                          let signature = delta["signature"] as? String
                                {
                                    thinkingSignatures[index, default: ""] += signature
                                } else if deltaType == "input_json_delta",
                                          let index = event["index"] as? Int,
                                          let partial = delta["partial_json"] as? String
                                {
                                    activeToolBlocks[index]?.jsonAccumulator += partial
                                }
                            }

                        case "content_block_stop":
                            let stoppedIndex = event["index"] as? Int ?? -1
                            let wasThinking = activeThinkingBlocks.remove(stoppedIndex) != nil

                            if wasThinking {
                                // Save thinking block for multi-turn continuity.
                                var thinkingBlock: [String: Any] = [
                                    "type": "thinking",
                                    "thinking": thinkingAccumulators.removeValue(forKey: stoppedIndex) ?? "",
                                ]
                                if let sig = thinkingSignatures.removeValue(forKey: stoppedIndex) {
                                    thinkingBlock["signature"] = sig
                                }
                                assistantContentBlocks.append(thinkingBlock)
                            }

                            // Flush accumulated text when a text block ends (not a tool or thinking block).
                            if !textAccumulator.isEmpty, !wasThinking, activeToolBlocks[stoppedIndex] == nil {
                                assistantContentBlocks.append([
                                    "type": "text",
                                    "text": textAccumulator,
                                ])
                                textAccumulator = ""
                            }

                            if let toolBlock = activeToolBlocks.removeValue(forKey: stoppedIndex)
                            {
                                // Emit the completed tool call
                                continuation.yield(.toolCall(
                                    id: toolBlock.id,
                                    name: toolBlock.name,
                                    arguments: toolBlock.jsonAccumulator
                                ))
                                // Record the tool_use block for conversation state
                                var argsObj: Any = [String: Any]()
                                if let argsData = toolBlock.jsonAccumulator.data(using: .utf8),
                                   let parsed = try? JSONSerialization.jsonObject(with: argsData)
                                {
                                    argsObj = parsed
                                }
                                assistantContentBlocks.append([
                                    "type": "tool_use",
                                    "id": toolBlock.id,
                                    "name": toolBlock.name,
                                    "input": argsObj,
                                ])
                            }

                        case "message_stop":
                            // Persist the full exchange into conversation state.
                            // First, append the user message (or tool_result) that was sent.
                            let sentMessages = buildMessages(text, attachments: attachments, toolResults: toolResults)
                            if let lastSent = sentMessages.last {
                                self.conversationMessages.append(lastSent)
                            }

                            // Then append the assistant's response with all content blocks.
                            if !assistantContentBlocks.isEmpty {
                                self.conversationMessages.append([
                                    "role": "assistant",
                                    "content": assistantContentBlocks,
                                ])
                            }

                        default:
                            break
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func clearConversation() async {
        conversationMessages = []
    }
}

enum AnthropicError: LocalizedError {
    case httpError(statusCode: Int)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Anthropic API returned HTTP \(code)"
        case .missingAPIKey: "Anthropic API key is not configured"
        }
    }
}
