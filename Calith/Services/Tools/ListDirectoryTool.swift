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

@Generable(description: "Arguments for listing directory contents")
struct ListDirectoryArguments {
    @Guide(description: "The absolute path to the directory to list")
    var path: String

    @Guide(description: "Whether to include hidden files (defaults to false)")
    var showHidden: Bool?
}

struct ListDirectoryTool: Tool {
    let description = "Lists the contents of a directory"

    func call(arguments: ListDirectoryArguments) async throws -> String {
        do {
            let url = URL(filePath: arguments.path)
            let fm = FileManager.default

            var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
            if !(arguments.showHidden ?? false) {
                options.insert(.skipsHiddenFiles)
            }

            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: options
            )

            let entries = try contents
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { url -> String in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    let isDir = values.isDirectory ?? false
                    let size = values.fileSize ?? 0
                    let suffix = isDir ? "/" : " (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
                    return "\(url.lastPathComponent)\(suffix)"
                }

            if entries.isEmpty {
                return "(empty directory)"
            }
            return entries.joined(separator: "\n")
        } catch {
            return "Error: Could not list directory at \(arguments.path) — \(error.localizedDescription)"
        }
    }
}
