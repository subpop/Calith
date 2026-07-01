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

@Generable(description: "Arguments for reading a file")
struct ReadFileArguments {
    @Guide(description: "The absolute path to the file to read")
    var path: String
}

struct ReadFileTool: Tool {
    let description = "Reads the contents of a file at the given path"

    func call(arguments: ReadFileArguments) async throws -> String {
        let url = URL(filePath: arguments.path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return "Error: Could not read file at \(arguments.path) — \(error.localizedDescription)"
        }
        guard let content = String(data: data, encoding: .utf8) else {
            return "[Binary file, \(data.count) bytes]"
        }
        if content.count > 50_000 {
            return String(content.prefix(50_000)) + "\n\n[Truncated at 50,000 characters]"
        }
        return content
    }
}
