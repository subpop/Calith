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

struct ConversationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var searchText = ""

    var onSelect: (Conversation) -> Void
    var onDelete: (Conversation) -> Void

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        if conversations.isEmpty {
            ContentUnavailableView(
                "No Conversations",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Your conversation history will appear here.")
            )
        } else {
            List {
                ForEach(filteredConversations) { conversation in
                    Button {
                        onSelect(conversation)
                    } label: {
                        ConversationHistoryRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let conversation = filteredConversations[index]
                        onDelete(conversation)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
        }
    }
}

private struct ConversationHistoryRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                Text("\u{00B7}")
                Text("\(conversation.messages.count) messages")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview("With Conversations") {
    let container = try! ModelContainer(
        for: Conversation.self, Message.self, Memory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let titles = [
        "Help me write a SwiftUI app",
        "Explain async/await in Swift",
        "Debug my Core Data migration",
        "What is the Liquid Glass design?",
        "Recipe ideas for dinner tonight",
    ]
    for (i, title) in titles.enumerated() {
        let conversation = Conversation(title: title)
        conversation.updatedAt = Calendar.current.date(byAdding: .hour, value: -i * 3, to: .now)!
        context.insert(conversation)
    }

    return ConversationHistoryView(
        onSelect: { _ in },
        onDelete: { _ in }
    )
    .modelContainer(container)
    .frame(width: 300, height: 400)
}

#Preview("No Conversations") {
    ConversationHistoryView(
        onSelect: { _ in },
        onDelete: { _ in }
    )
    .modelContainer(for: [Conversation.self, Message.self, Memory.self], inMemory: true)
    .frame(width: 300, height: 400)
}
