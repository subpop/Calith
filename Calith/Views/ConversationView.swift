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

struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ConversationViewModel()
    @State private var scrollPosition = ScrollPosition()
    @State private var showingHistory = false
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var isDropTargeted = false

    private static let greetingMessage = Message(
        role: "assistant",
        content: """
        Hi, I'm Calith — a virtual assistant. Here are a few things I can help with:

        - **Look things up** on the web or in files on your Mac
        - **Get things done** like organizing files, running projects, or checking on your system
        - **Find anything** on your Mac — documents, folders, whatever you need
        - **Automate your workflow** by controlling apps and performing tasks for you

        What can I help you with?
        """
    )

    private var conversationTitle: String {
        viewModel.currentConversation?.title ?? "New Conversation"
    }

    private var attachmentsEnabled: Bool {
        viewModel.activeProvider != nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.messages.isEmpty {
                    MessageBubble(message: Self.greetingMessage)
                }

                ForEach(viewModel.messages) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                }

                if let pending = viewModel.toolExecutor.pendingConfirmation {
                    ToolConfirmationCard(
                        toolName: pending.name,
                        arguments: pending.arguments,
                        onApprove: { viewModel.approveToolCall() },
                        onDeny: { viewModel.denyToolCall() }
                    )
                }

                if viewModel.isResponding && (!viewModel.isStreamingEmpty || !viewModel.isThinkingEmpty) {
                    StreamingMessageView(
                        blocks: viewModel.streamingBlocks,
                        pending: viewModel.streamingPending,
                        characterCount: viewModel.streamingCharacterCount,
                        thinkingText: viewModel.thinkingContent,
                        thinkingBlocks: viewModel.thinkingBlocks,
                        thinkingPending: viewModel.thinkingPending,
                        thinkingCharacterCount: viewModel.thinkingCharacterCount
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.2), value: viewModel.isStreamingEmpty)
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.messages.count) {
            scrollToBottom()
        }
        .onChange(of: viewModel.streamingCharacterCount) {
            scrollToBottom()
        }
        .onChange(of: viewModel.thinkingCharacterCount) {
            scrollToBottom()
        }
        .safeAreaInset(edge: .bottom) {
            MessageInputView(
                isAnimating: viewModel.isResponding,
                attachmentsEnabled: attachmentsEnabled,
                attachments: $stagedAttachments
            ) { text, staged in
                let attachments = staged.map { $0.toAttachment() }
                viewModel.send(text, attachments: attachments, context: modelContext)
            } onCancel: {
                viewModel.cancel(context: modelContext)
            }
            .padding()
        }
        .onDrop(
            of: StagedAttachment.dropTypes,
            isTargeted: Binding(
                get: { isDropTargeted },
                set: { targeted in
                    guard attachmentsEnabled else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        isDropTargeted = targeted
                    }
                }
            )
        ) { providers in
            guard attachmentsEnabled, !providers.isEmpty else { return false }
            DropHandler.handleProviders(providers) { staged in
                stagedAttachments.append(contentsOf: staged)
            }
            return true
        }
        .overlay {
            if attachmentsEnabled, isDropTargeted {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()

                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Drop files to attach")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 320, minHeight: 440)
        .navigationTitle(conversationTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("New Conversation", systemImage: "square.and.pencil") {
                    Task {
                        await viewModel.newConversation(context: modelContext)
                    }
                }
                .disabled(viewModel.isResponding)
            }

            ToolbarItem(placement: .primaryAction) {
                Button("History", systemImage: "clock") {
                    showingHistory = true
                }
                .popover(isPresented: $showingHistory) {
                    ConversationHistoryView(
                        onSelect: { conversation in
                            showingHistory = false
                            Task {
                                await viewModel.switchConversation(to: conversation, context: modelContext)
                            }
                        },
                        onDelete: { conversation in
                            viewModel.deleteConversation(conversation, context: modelContext)
                        }
                    )
                    .frame(width: 300, height: 400)
                }
            }
        }
    }

    private func scrollToBottom() {
        withAnimation {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}

#Preview("Empty") {
    ConversationView()
        .modelContainer(for: [Conversation.self, Message.self, Memory.self, Attachment.self], inMemory: true)
}

#Preview("With Messages") {
    ConversationView()
        .modelContainer(for: [Conversation.self, Message.self, Memory.self, Attachment.self], inMemory: true) { result in
            if case .success(let container) = result {
                let context = ModelContext(container)
                let conversation = Conversation(title: "Getting started")
                context.insert(conversation)

                let m1 = Message(role: "user", content: "Hello! What can you help me with?")
                m1.conversation = conversation
                context.insert(m1)

                let m2 = Message(role: "assistant", content: "I can help you with a variety of tasks including running commands, reading and writing files, and executing AppleScript. What would you like to do?")
                m2.conversation = conversation
                context.insert(m2)

                let m3 = Message(role: "user", content: "Can you list the files in my home directory?")
                m3.conversation = conversation
                context.insert(m3)

                try? context.save()
            }
        }
}

