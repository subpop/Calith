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
import os
import SwiftData

/// Structured output for memory extraction from conversations.
@Generable(description: "Facts extracted from a conversation exchange")
struct ExtractedMemories {
    @Guide(description: "Array of facts learned about the user. Each should be a short, standalone statement.")
    var facts: [ExtractedFact]
}

@Generable(description: "A single fact about the user")
struct ExtractedFact {
    @Guide(description: "The fact itself, e.g. 'User prefers dark mode' or 'User's name is Alex'")
    var fact: String

    @Guide(description: "Category: preference, personal, technical, project, or general")
    var category: String
}

/// Extracts and persists facts about the user from conversation exchanges.
final class MemoryService: Sendable {
    private let embeddingService = EmbeddingService()

    /// Extracts memories from a user message + assistant response pair.
    /// Runs in the background and does not block the conversation.
    func extractMemories(
        userMessage: String,
        assistantResponse: String,
        context: ModelContext
    ) {
        Task {
            do {
                let session = LanguageModelSession(instructions: """
                    Extract facts about the user from this conversation exchange. \
                    Only extract concrete, reusable facts (preferences, personal info, \
                    technical setup, project details). Do NOT extract transient requests \
                    or conversational filler. If no facts are present, return an empty array.
                    """)

                let prompt = """
                    User: \(userMessage)

                    Assistant: \(assistantResponse)
                    """

                let response = try await session.respond(
                    to: prompt,
                    generating: ExtractedMemories.self
                )

                let extracted = response.content

                guard !extracted.facts.isEmpty else { return }

                let existingDescriptor = FetchDescriptor<Memory>()
                let existing = (try? context.fetch(existingDescriptor)) ?? []
                let existingFacts = Set(existing.map { $0.fact.lowercased() })

                for item in extracted.facts {
                    let normalized = item.fact.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty,
                          !existingFacts.contains(normalized.lowercased())
                    else { continue }

                    let memory = Memory(
                        fact: normalized,
                        category: item.category,
                        source: String(userMessage.prefix(100))
                    )

                    if let vector = self.embeddingService.embed(normalized) {
                        memory.embedding = self.embeddingService.serialize(vector)
                    }

                    context.insert(memory)
                }
                try? context.save()
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "Calith", category: "MemoryService")
                    .error("Memory extraction failed: \(error)")
            }
        }
    }
}
