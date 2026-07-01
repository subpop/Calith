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

final class OllamaService: LLMService, @unchecked Sendable {
    private var conversationMessages: [[String: Any]] = []
    private var baseURL: String = "http://localhost:11434"
    private var model: String = "llama3.1"
    /// Context window size in tokens. Ollama defaults to 2048 when not specified.
    private var contextWindowSize: Int?

    func configure(baseURL: String, model: String, contextWindowSize: Int? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.contextWindowSize = contextWindowSize
    }

    // MARK: - Request building

    private func buildSystemMessage(memories: [Memory], location: String?) -> [String: Any] {
        var parts = basePrompt

        if !memories.isEmpty {
            let facts = memories.map { "- \($0.fact)" }.joined(separator: "\n")
            parts.append("Known facts about the user:\n\(facts)")
        }

        if let location {
            parts.append("The user's current location is \(location).")
        }

        return [
            "role": "system",
            "content": parts.joined(separator: "\n\n"),
        ]
    }

    private func buildMessages(
        _ text: String,
        attachments: [Attachment],
        memories: [Memory],
        location: String?,
        toolResults: [ToolResult]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = [buildSystemMessage(memories: memories, location: location)]
        messages.append(contentsOf: conversationMessages)

        if !toolResults.isEmpty {
            for result in toolResults {
                messages.append([
                    "role": "tool",
                    "content": result.output,
                ])
            }
        } else {
            // Build user message, optionally with image attachments
            var userMessage: [String: Any] = [
                "role": "user",
                "content": text,
            ]

            // Ollama supports images as base64 strings in an "images" array.
            // Text files are inlined into the content. PDFs are noted but not sent.
            var images: [String] = []
            var extraContent = ""

            for attachment in attachments {
                if attachment.isImage {
                    images.append(attachment.data.base64EncodedString())
                } else if attachment.isText, let textContent = String(data: attachment.data, encoding: .utf8) {
                    extraContent += "\n\n[\(attachment.filename)]:\n\(textContent)"
                } else if attachment.isPDF {
                    extraContent += "\n\n[Attached PDF: \(attachment.filename) — PDF viewing not supported by this model]"
                }
            }

            if !extraContent.isEmpty {
                userMessage["content"] = text + extraContent
            }

            if !images.isEmpty {
                userMessage["images"] = images
            }

            messages.append(userMessage)
        }

        return messages
    }

    private func buildToolDefinitions(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let paramsData = tool.parametersSchema.data(using: .utf8),
                  let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
            else { return nil }

            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": params,
                ] as [String: Any],
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
                    let messages = buildMessages(text, attachments: attachments, memories: memories, location: location, toolResults: toolResults)
                    let toolDefs = buildToolDefinitions(tools)

                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true,
                        "think": true,
                    ]

                    if !toolDefs.isEmpty {
                        body["tools"] = toolDefs
                    }

                    if let numCtx = self.contextWindowSize {
                        body["options"] = ["num_ctx": numCtx]
                    }

                    let bodyData = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: URL(string: "\(baseURL)/api/chat")!)
                    request.httpMethod = "POST"
                    request.httpBody = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw OllamaError.httpError(statusCode: statusCode)
                    }

                    // Parse newline-delimited JSON stream (Ollama native format).
                    var textContent = ""
                    var thinkingContent = ""
                    var completedToolCalls: [[String: Any]] = []

                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = chunk["message"] as? [String: Any]
                        else { continue }

                        // Thinking content
                        if let thinking = message["thinking"] as? String, !thinking.isEmpty {
                            thinkingContent += thinking
                            continuation.yield(.thinkingDelta(thinking))
                        }

                        // Text content
                        if let content = message["content"] as? String, !content.isEmpty {
                            textContent += content
                            continuation.yield(.textDelta(content))
                        }

                        // Tool calls (delivered as complete objects, not streamed)
                        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                            for tc in toolCalls {
                                guard let funcInfo = tc["function"] as? [String: Any],
                                      let name = funcInfo["name"] as? String
                                else { continue }

                                // Ollama returns arguments as parsed JSON; serialize to string.
                                let arguments = funcInfo["arguments"]
                                let argsString: String
                                if let argsDict = arguments,
                                   let argsData = try? JSONSerialization.data(withJSONObject: argsDict)
                                {
                                    argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                                } else {
                                    argsString = "{}"
                                }

                                let callID = UUID().uuidString
                                continuation.yield(.toolCall(id: callID, name: name, arguments: argsString))
                                completedToolCalls.append([
                                    "function": [
                                        "name": name,
                                        "arguments": arguments as Any,
                                    ],
                                ])
                            }
                        }

                        // Check for done
                        if chunk["done"] as? Bool == true {
                            break
                        }
                    }

                    // Update conversation state — append the user/tool messages that were sent,
                    // then the assistant's response.
                    if !toolResults.isEmpty {
                        for result in toolResults {
                            self.conversationMessages.append([
                                "role": "tool",
                                "content": result.output,
                            ])
                        }
                    } else {
                        self.conversationMessages.append([
                            "role": "user",
                            "content": text,
                        ])
                    }

                    // Build the assistant message for state.
                    var assistantMsg: [String: Any] = ["role": "assistant"]
                    if !textContent.isEmpty {
                        assistantMsg["content"] = textContent
                    }
                    if !thinkingContent.isEmpty {
                        assistantMsg["thinking"] = thinkingContent
                    }
                    if !completedToolCalls.isEmpty {
                        assistantMsg["tool_calls"] = completedToolCalls
                    }
                    self.conversationMessages.append(assistantMsg)

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

enum OllamaError: LocalizedError {
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Ollama returned HTTP \(code)"
        }
    }
}
