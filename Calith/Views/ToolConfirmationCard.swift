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

/// Inline permission request shown when a tool call requires user confirmation before execution.
/// Styled as a conversational message from the assistant with capsule Yes/No buttons.
struct ToolConfirmationCard: View {
    let toolName: String
    let arguments: String
    let onApprove: () -> Void
    let onDeny: () -> Void

    private let buttonWidth = 180.0
    private let buttonHeight = 40.0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Text((try? ToolDescription.permissionQuestion(toolName: toolName, arguments: arguments)) ?? AttributedString("May I run \(toolName)?"))

                HStack(spacing: 12) {
                    Button("No", action: onDeny)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(
                            .linearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                            in: .capsule
                        )

                    Button("Yes", action: onApprove)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .foregroundStyle(.white)
                        .background(
                            .linearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))

            Spacer(minLength: 60)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ToolConfirmationCard(
            toolName: "RunCommand",
            arguments: "{\"command\":\"ls -la /Users/link/Projects\"}",
            onApprove: {},
            onDeny: {}
        )

        ToolConfirmationCard(
            toolName: "ReadFile",
            arguments: "{\"path\":\"/Users/link/TODO.txt\"}",
            onApprove: {},
            onDeny: {}
        )

        ToolConfirmationCard(
            toolName: "RunAppleScript",
            arguments: "{\"source\":\"tell application \\\"Finder\\\" to get name of every disk\"}",
            onApprove: {},
            onDeny: {}
        )
    }
    .padding()
}

