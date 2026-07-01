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
import FoundationModels

final class FoundationModelService: LLMService, @unchecked Sendable {
    private var session: LanguageModelSession?
    private var activeTools: [any Tool] = []

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

    /// Configures the Foundation Models tools to use. Call before starting a conversation.
    func setTools(_ tools: [any Tool]) {
        activeTools = tools
    }

    private func getOrCreateSession(memories: [Memory], location: String?) -> LanguageModelSession {
        if let session {
            return session
        }
        let instructions = buildInstructions(memories: memories, location: location)
        let newSession = LanguageModelSession(tools: activeTools, instructions: instructions)
        session = newSession
        return newSession
    }

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
            let session = self.getOrCreateSession(memories: memories, location: location)

            Task {
                do {
                    let stream = session.streamResponse(to: text)
                    var lastContent = ""

                    for try await snapshot in stream {
                        let newText = String(snapshot.content.dropFirst(lastContent.count))
                        if !newText.isEmpty {
                            continuation.yield(.textDelta(newText))
                        }
                        lastContent = snapshot.content
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
        session = nil
    }
}
