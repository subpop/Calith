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

import SwiftData
import SwiftUI
import Textual

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }

            MessageContent(message: message)
                .padding(12)
                .background(bubbleBackground, in: .rect(cornerRadius: 12))

            if message.role != "user" {
                Spacer(minLength: 60)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case "user":
            AnyShapeStyle(.tint.opacity(0.4))
        case "tool":
            AnyShapeStyle(.fill.quinary)
        default:
            AnyShapeStyle(.fill.quaternary)
        }
    }
}

private struct MessageContent: View {
    let message: Message

    var body: some View {
        switch message.role {
        case "user":
            VStack(alignment: .trailing, spacing: 8) {
                if !message.content.isEmpty {
                    Text(message.content)
                }
                if !message.attachments.isEmpty {
                    MessageAttachmentsView(attachments: message.attachments)
                }
            }

        case "tool":
            ToolSummaryLabel(message: message)

        default: // assistant
            VStack(alignment: .leading, spacing: 8) {
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    ThinkingDisclosureView(text: thinking, isExpanded: false)
                }
                StructuredText(markdown: message.content)
                    .textual.textSelection(.enabled)
            }
        }
    }
}

/// Renders attachment thumbnails inline within a message bubble.
private struct MessageAttachmentsView: View {
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(attachments) { attachment in
                if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 200)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    Label(attachment.filename, systemImage: attachment.isPDF ? "doc.richtext" : "doc.text")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.fill.quinary, in: .capsule)
                }
            }
        }
    }
}

struct StreamingMessageView: View {
    let blocks: [String]
    let pending: String
    let characterCount: Int
    var thinkingText: String = ""
    var thinkingBlocks: [String] = []
    var thinkingPending: String = ""
    var thinkingCharacterCount: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if !thinkingText.isEmpty {
                    ThinkingDisclosureView(
                        text: thinkingText,
                        isExpanded: true,
                        blocks: thinkingBlocks,
                        pending: thinkingPending,
                        characterCount: thinkingCharacterCount
                    )
                }

                ForEach(blocks.enumerated(), id: \.element) { _, block in
                    StructuredText(markdown: block)
                }

                if !pending.isEmpty {
                    StructuredText(markdown: pending)
                }
            }
            .textual.textSelection(.enabled)
            .textRenderer(StreamingTextRenderer(characterCount: Double(characterCount)))
            .animation(.easeIn(duration: 0.3), value: characterCount)
            .padding(12)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))

            Spacer(minLength: 60)
        }
    }
}

/// Displays a one-line summary of a completed tool call, e.g. "Read the file ~/TODO.txt".
private struct ToolSummaryLabel: View {
    let message: Message

    var body: some View {
        let toolName = message.toolName ?? "Tool"
        let icon = ToolDescription.iconName(for: toolName)

        if message.content == "Tool call denied by user." {
            let summary = (try? ToolDescription.summary(toolName: toolName, arguments: message.toolArguments)) ?? AttributedString(toolName)
            HStack(alignment: .center) {
                Label {
                    Text("Denied: " + summary)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "xmark")
            }
        } else {
            let summary = (try? ToolDescription.summary(toolName: toolName, arguments: message.toolArguments)) ?? AttributedString(toolName)
            HStack(alignment: .center) {
                Label {
                    Text(summary)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "checkmark")
            }
        }
    }
}

struct ThinkingDisclosureView: View {
    let text: String
    var isExpanded: Bool = false
    var blocks: [String]? = nil
    var pending: String = ""
    var characterCount: Int = 0

    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Group {
                if let blocks {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(blocks.enumerated(), id: \.element) { _, block in
                            StructuredText(markdown: block)
                        }
                        if !pending.isEmpty {
                            StructuredText(markdown: pending)
                        }
                    }
                    .textual.textSelection(.enabled)
                    .textRenderer(StreamingTextRenderer(characterCount: Double(characterCount)))
                    .animation(.easeIn(duration: 0.3), value: characterCount)
                } else {
                    StructuredText(markdown: text)
                        .textual.textSelection(.enabled)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } label: {
            Label("Thinking", systemImage: "bubble.left")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.fill.quinary, in: .rect(cornerRadius: 8))
        .onAppear {
            expanded = isExpanded
        }
    }
}

#Preview("Initial Message") {
    ConversationView()
        .modelContainer(for: [Message.self, Memory.self, Attachment.self], inMemory: true)
}

#Preview("Conversation") {
    ScrollView {
        VStack(spacing: 12) {
            MessageBubble(message: Message(
                role: "user",
                content: "Hey! Can you help me read a file and summarize it?"
            ))
            MessageBubble(message: Message(
                role: "assistant",
                content: "Sure! Let me read that file for you.",
                thinkingContent: "The user wants me to read a file and provide a summary. I should use the ReadFile tool."
            ))
            MessageBubble(message: Message(
                role: "tool",
                content: "File contents here...",
                toolName: "ReadFile",
                toolArguments: "{\"path\": \"~/Documents/notes.txt\"}"
            ))
            MessageBubble(message: Message(
                role: "assistant",
                content: """
                Here's a summary of `notes.txt`:

                - **Project kickoff** is scheduled for next Monday
                - The team agreed on a *SwiftUI-first* approach
                - Open questions remain about the networking layer

                Let me know if you'd like more detail on any of these points!
                """
            ))
            MessageBubble(message: Message(
                role: "user",
                content: "That's great, thanks! Can you search for SwiftUI best practices?"
            ))
            MessageBubble(message: Message(
                role: "tool",
                content: "Search results...",
                toolName: "WebSearch",
                toolArguments: "{\"query\": \"SwiftUI best practices 2026\"}"
            ))
            MessageBubble(message: Message(
                role: "assistant",
                content: """
                Here are the top recommendations:

                1. Use `@Observable` instead of `ObservableObject`
                2. Prefer `NavigationStack` over the deprecated `NavigationView`
                3. Keep views small and compose them together
                """
            ))
        }
        .padding()
    }
    .frame(width: 500, height: 700)
    .modelContainer(for: [Message.self, Attachment.self], inMemory: true)
}

#Preview("Thinking Disclosure") {
    VStack(spacing: 12) {
        ThinkingDisclosureView(
            text: "The user is greeting me. I should respond warmly and offer to help.",
            isExpanded: true
        )
        ThinkingDisclosureView(
            text: "Let me analyze this step by step. First, I need to consider the algorithm complexity.",
            isExpanded: false
        )
    }
    .padding()
    .frame(width: 400)
}
#Preview("Tool Summary Labels") {
    VStack(alignment: .leading, spacing: 12) {
        MessageBubble(message: Message(
            role: "tool",
            content: "File contents here...",
            toolName: "ReadFile",
            toolArguments: "{\"path\": \"~/Projects/TODO.txt\"}"
        ))
        MessageBubble(message: Message(
            role: "tool",
            content: "Tool call denied by user.",
            toolName: "RunCommand",
            toolArguments: "{\"command\": \"rm -rf /\"}"
        ))
        MessageBubble(message: Message(
            role: "tool",
            content: "Search results...",
            toolName: "WebSearch",
            toolArguments: "{\"query\": \"SwiftUI previews\"}"
        ))
        MessageBubble(message: Message(
            role: "tool",
            content: "Listed contents...",
            toolName: "ListDirectory",
            toolArguments: "{\"path\": \"~/Documents\"}"
        ))
    }
    .padding()
    .frame(width: 400)
    .modelContainer(for: [Message.self, Attachment.self], inMemory: true)
}

#Preview("Message Attachments") {
    let imageData: Data = {
        let symbol = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil)!
        let size = NSSize(width: 200, height: 150)
        let image = NSImage(size: size)
        image.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image.tiffRepresentation ?? Data()
    }()

    VStack(spacing: 12) {
        MessageBubble(message: Message(
            role: "user",
            content: "Here's a photo",
            attachments: [
                Attachment(mimeType: "image/tiff", filename: "photo.tiff", data: imageData),
            ]
        ))

        MessageBubble(message: Message(
            role: "user",
            content: "Check these docs",
            attachments: [
                Attachment(mimeType: "application/pdf", filename: "report.pdf", data: Data()),
                Attachment(mimeType: "text/plain", filename: "notes.txt", data: Data()),
            ]
        ))

        MessageBubble(message: Message(
            role: "user",
            content: "",
            attachments: [
                Attachment(mimeType: "image/tiff", filename: "screenshot.tiff", data: imageData),
                Attachment(mimeType: "application/pdf", filename: "invoice.pdf", data: Data()),
            ]
        ))
    }
    .padding()
    .frame(width: 400)
    .modelContainer(for: [Message.self, Attachment.self], inMemory: true)
}

