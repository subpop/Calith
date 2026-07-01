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

final class OpenAIService: LLMService, @unchecked Sendable {
    private var conversationState: [[String: Any]] = []
    private var apiKey: String
    private var baseURL: String
    private var model: String
    private var requiresAPIKey: Bool
    private var contextTokenLimit: Int?

    init(apiKey: String = "", baseURL: String = "https://api.openai.com/v1", model: String = "gpt-4o", requiresAPIKey: Bool = true, contextTokenLimit: Int? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.requiresAPIKey = requiresAPIKey
        self.contextTokenLimit = contextTokenLimit
    }

    func configure(apiKey: String, baseURL: String, model: String, requiresAPIKey: Bool, contextTokenLimit: Int? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.requiresAPIKey = requiresAPIKey
        self.contextTokenLimit = contextTokenLimit
    }

    // MARK: - Request building

    private func buildInstructions(memories: [Memory], location: String?) -> String {
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

    private func buildInput(
        _ text: String,
        attachments: [Attachment],
        history: [Message],
        toolResults: [ToolResult]
    ) -> [[String: Any]] {
        var input: [[String: Any]] = conversationState

        // Append tool results if any
        for result in toolResults {
            input.append([
                "type": "function_call_output",
                "call_id": result.toolCallID,
                "output": result.output,
            ])
        }

        // Append user message if not a tool result continuation
        if toolResults.isEmpty {
            if attachments.isEmpty {
                input.append([
                    "role": "user",
                    "content": text,
                ])
            } else {
                // Multi-modal: build a content array with text + attachment blocks
                var content: [[String: Any]] = []

                for attachment in attachments {
                    let base64 = attachment.data.base64EncodedString()
                    let dataURL = "data:\(attachment.mimeType);base64,\(base64)"

                    if attachment.isImage {
                        content.append([
                            "type": "input_image",
                            "image_url": dataURL,
                        ])
                    } else if attachment.isPDF || attachment.isText {
                        content.append([
                            "type": "input_file",
                            "file_data": dataURL,
                        ])
                    }
                }

                if !text.isEmpty {
                    content.append([
                        "type": "input_text",
                        "text": text,
                    ])
                }

                input.append([
                    "role": "user",
                    "content": content,
                ])
            }
        }

        return input
    }

    private func buildToolDefinitions(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let paramsData = tool.parametersSchema.data(using: .utf8),
                  let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
            else { return nil }

            return [
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": params,
            ] as [String: Any]
        }
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
                    guard URL(string: self.baseURL) != nil, !self.requiresAPIKey || !self.apiKey.isEmpty  else {
                        throw OpenAIError.missingAPIKey
                    }

                    let input = buildInput(text, attachments: attachments, history: history, toolResults: toolResults)
                    let instructions = buildInstructions(memories: memories, location: location)
                    let toolDefs = buildToolDefinitions(tools)

                    var body: [String: Any] = [
                        "model": model,
                        "instructions": instructions,
                        "input": input,
                        "stream": true,
                        "reasoning": ["summary": "auto"],
                    ]

                    if !toolDefs.isEmpty {
                        body["tools"] = toolDefs
                    }

                    if let limit = self.contextTokenLimit {
                        body["context_management"] = [
                            ["type": "compaction", "compact_threshold": limit]
                        ]
                    }

                    let bodyData = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: URL(string: "\(baseURL)/responses")!)
                    request.httpMethod = "POST"
                    request.httpBody = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw OpenAIError.httpError(statusCode: statusCode)
                    }

                    // Parse SSE stream
                    var toolCallBuffers: [String: (name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let data = jsonString.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String
                        else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.reasoning_summary_text.delta":
                            if let delta = event["delta"] as? String {
                                continuation.yield(.thinkingDelta(delta))
                            }

                        case "response.output_item.added":
                            if let item = event["item"] as? [String: Any],
                               item["type"] as? String == "function_call",
                               let id = item["call_id"] as? String,
                               let name = item["name"] as? String
                            {
                                toolCallBuffers[id] = (name: name, arguments: "")
                            }

                        case "response.function_call_arguments.delta":
                            if let callID = event["call_id"] as? String ?? (event["item_id"] as? String),
                               let delta = event["delta"] as? String,
                               var buffer = toolCallBuffers[callID]
                            {
                                buffer.arguments += delta
                                toolCallBuffers[callID] = buffer
                            }

                        case "response.function_call_arguments.done":
                            if let callID = event["call_id"] as? String ?? (event["item_id"] as? String),
                               let buffer = toolCallBuffers[callID]
                            {
                                continuation.yield(.toolCall(
                                    id: callID,
                                    name: buffer.name,
                                    arguments: buffer.arguments
                                ))
                            }

                        case "response.completed":
                            // Capture output items for manual state management
                            if let responseObj = event["response"] as? [String: Any],
                               let output = responseObj["output"] as? [[String: Any]]
                            {
                                self.conversationState = input
                                for item in output {
                                    self.conversationState.append(item)
                                }
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
        conversationState = []
    }
}

enum OpenAIError: LocalizedError {
    case httpError(statusCode: Int)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "OpenAI API returned HTTP \(code)"
        case .missingAPIKey: "OpenAI API key is not configured"
        }
    }
}
