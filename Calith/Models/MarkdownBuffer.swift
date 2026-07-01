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

struct MarkdownBuffer {
    private var rawBuffer = ""
    private(set) var blocks: [String] = []
    private(set) var pending: String = ""
    private var cachedCharacterCount = 0
    private var inCodeFence = false

    var isEmpty: Bool { rawBuffer.isEmpty }
    var content: String { rawBuffer }
    var characterCount: Int { cachedCharacterCount }

    mutating func append(_ delta: String) {
        rawBuffer += delta
        cachedCharacterCount += delta.count

        // Incremental parse: only re-scan pending + new delta, not the entire buffer.
        let combined = pending + delta
        var newLines: [Substring] = []

        for line in combined.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.drop(while: \.isWhitespace).hasPrefix("```") {
                inCodeFence.toggle()
            }

            if line.isEmpty && !inCodeFence {
                if !newLines.isEmpty {
                    blocks.append(newLines.joined(separator: "\n"))
                    newLines = []
                }
            } else {
                newLines.append(line)
            }
        }

        pending = newLines.joined(separator: "\n")
    }

    mutating func flush() {
        if !pending.isEmpty {
            blocks.append(pending)
            pending = ""
        }
    }

    mutating func reset() {
        rawBuffer = ""
        blocks = []
        pending = ""
        cachedCharacterCount = 0
        inCodeFence = false
    }
}
