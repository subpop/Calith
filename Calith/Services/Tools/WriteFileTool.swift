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

@Generable(description: "Arguments for writing content to a file")
struct WriteFileArguments {
    @Guide(description: "The absolute path to the file to write")
    var path: String

    @Guide(description: "The text content to write to the file")
    var content: String
}

struct WriteFileTool: Tool {
    let description = "Writes text content to a file at the given path, creating it if needed"

    func call(arguments: WriteFileArguments) async throws -> String {
        do {
            let url = URL(filePath: arguments.path)
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try arguments.content.write(to: url, atomically: true, encoding: .utf8)
            return "Wrote \(arguments.content.count) characters to \(arguments.path)"
        } catch {
            return "Error: Could not write file at \(arguments.path) — \(error.localizedDescription)"
        }
    }
}
