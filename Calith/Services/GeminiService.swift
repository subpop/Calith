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

final class GeminiService: LLMService, @unchecked Sendable {
    private var conversationContents: [[String: Any]] = []
    private var apiKey: String = ""
    private var baseURL: String = "https://generativelanguage.googleapis.com/v1beta"
    private var model: String = "gemini-2.5-flash"
    /// Maximum number of tokens the model may generate in a single response.
    private var maxOutputTokens: Int = 8192

    func configure(apiKey: String, baseURL: String, model: String, maxOutputTokens: Int = 8192) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
    }

    // MARK: - Request building

    private func buildSystemInstruction(memories: [Memory], location: String?) -> [String: Any] {
        var parts = basePrompt

        if !memories.isEmpty {
            let facts = memories.map { "- \($0.fact)" }.joined(separator: "\n")
            parts.append("Known facts about the user:\n\(facts)")
        }

        if let location {
            parts.append("The user's current location is \(location).")
        }

        let text = parts.joined(separator: "\n\n")
        return [
            "parts": [["text": text]],
        ]
    }

    private func buildToolDeclarations(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let paramsData = tool.parametersSchema.data(using: .utf8),
                  let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]
            else { return nil }

            return [
                "name": tool.name,
                "description": tool.description,
                "parameters": Self.convertToGeminiSchema(params),
            ] as [String: Any]
        }
    }

    /// Converts a standard JSON Schema dict to Gemini's Schema format:
    /// uppercase type values and strips unsupported keys like `additionalProperties`.
    private static func convertToGeminiSchema(_ schema: [String: Any]) -> [String: Any] {
        var result = schema
        result.removeValue(forKey: "additionalProperties")

        if let type = result["type"] as? String {
            result["type"] = type.uppercased()
        }

        if var properties = result["properties"] as? [String: Any] {
            for (key, value) in properties {
                if let propSchema = value as? [String: Any] {
                    properties[key] = convertToGeminiSchema(propSchema)
                }
            }
            result["properties"] = properties
        }

        if var items = result["items"] as? [String: Any] {
            items = convertToGeminiSchema(items)
            result["items"] = items
        }

        return result
    }

    private func buildContents(
        _ text: String,
        attachments: [Attachment],
        toolResults: [ToolResult]
    ) -> [[String: Any]] {
        var contents = conversationContents

        if !toolResults.isEmpty {
            // Tool results are sent as a user turn with functionResponse parts.
            let parts: [[String: Any]] = toolResults.map { result in
                [
                    "functionResponse": [
                        "id": result.toolCallID,
                        "name": result.toolName,
                        "response": ["output": result.output],
                    ] as [String: Any],
                ]
            }
            contents.append([
                "role": "user",
                "parts": parts,
            ])
        } else {
            var parts: [[String: Any]] = []

            for attachment in attachments {
                if attachment.isText, let textContent = String(data: attachment.data, encoding: .utf8) {
                    parts.append(["text": "[\(attachment.filename)]:\n\(textContent)"])
                } else {
                    // Images and PDFs use inlineData
                    let base64 = attachment.data.base64EncodedString()
                    parts.append([
                        "inlineData": [
                            "mimeType": attachment.mimeType,
                            "data": base64,
                        ] as [String: Any],
                    ])
                }
            }

            if !text.isEmpty {
                parts.append(["text": text])
            }

            contents.append([
                "role": "user",
                "parts": parts,
            ])
        }

        return contents
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
                        throw GeminiError.missingAPIKey
                    }

                    let contents = buildContents(text, attachments: attachments, toolResults: toolResults)
                    let systemInstruction = buildSystemInstruction(memories: memories, location: location)
                    let functionDeclarations = buildToolDeclarations(tools)

                    let generationConfig: [String: Any] = [
                        "maxOutputTokens": maxOutputTokens,
                        "thinkingConfig": ["includeThoughts": true],
                    ]

                    var body: [String: Any] = [
                        "contents": contents,
                        "systemInstruction": systemInstruction,
                        "generationConfig": generationConfig,
                    ]

                    if !functionDeclarations.isEmpty {
                        body["tools"] = [
                            ["functionDeclarations": functionDeclarations],
                        ]
                    }

                    let bodyData = try JSONSerialization.data(withJSONObject: body)

                    let endpoint = "\(baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.httpBody = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        // Read the error body for a detailed message.
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        var detail: String?
                        if let data = errorBody.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String
                        {
                            detail = message
                        }
                        throw GeminiError.httpError(statusCode: statusCode, detail: detail)
                    }

                    // Parse SSE stream.
                    // Each `data: ` line is a full GenerateContentResponse JSON.
                    // candidates[0].content.parts[] contains the incremental parts.
                    var modelParts: [[String: Any]] = []

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard let data = jsonString.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = chunk["candidates"] as? [[String: Any]],
                              let candidate = candidates.first,
                              let content = candidate["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]]
                        else { continue }

                        for part in parts {
                            if let functionCall = part["functionCall"] as? [String: Any],
                               let name = functionCall["name"] as? String
                            {
                                let id = functionCall["id"] as? String ?? UUID().uuidString
                                let args: String
                                if let argsObj = functionCall["args"] {
                                    let argsData = try JSONSerialization.data(withJSONObject: argsObj)
                                    args = String(data: argsData, encoding: .utf8) ?? "{}"
                                } else {
                                    args = "{}"
                                }
                                modelParts.append(part)
                                continuation.yield(.toolCall(id: id, name: name, arguments: args))
                            } else if let text = part["text"] as? String {
                                let isThought = part["thought"] as? Bool ?? false
                                if isThought {
                                    continuation.yield(.thinkingDelta(text))
                                } else {
                                    continuation.yield(.textDelta(text))
                                }
                                modelParts.append(part)
                            }
                        }
                    }

                    // Persist the exchange into conversation state.
                    let sentContents = buildContents(text, attachments: attachments, toolResults: toolResults)
                    if let lastSent = sentContents.last {
                        self.conversationContents.append(lastSent)
                    }

                    if !modelParts.isEmpty {
                        // Strip thought signature data from stored parts to keep state clean.
                        let storedParts: [[String: Any]] = modelParts.map { part in
                            var cleaned = part
                            cleaned.removeValue(forKey: "thoughtSignature")
                            return cleaned
                        }
                        self.conversationContents.append([
                            "role": "model",
                            "parts": storedParts,
                        ])
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
        conversationContents = []
    }
}

enum GeminiError: LocalizedError {
    case httpError(statusCode: Int, detail: String?)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let detail):
            if let detail { "Gemini API returned HTTP \(code): \(detail)" }
            else { "Gemini API returned HTTP \(code)" }
        case .missingAPIKey: "Gemini API key is not configured"
        }
    }
}
