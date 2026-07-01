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
import SwiftData

@Model
final class Message {
    var id: UUID
    var role: String
    var content: String
    var thinkingContent: String?
    var timestamp: Date
    var toolCallID: String?
    var toolName: String?
    var toolArguments: String?
    var isToolConfirmationPending: Bool
    var conversation: Conversation?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment]

    init(
        role: String,
        content: String,
        thinkingContent: String? = nil,
        timestamp: Date = .now,
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolArguments: String? = nil,
        isToolConfirmationPending: Bool = false,
        attachments: [Attachment] = []
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolArguments = toolArguments
        self.isToolConfirmationPending = isToolConfirmationPending
        self.attachments = attachments
    }
}
