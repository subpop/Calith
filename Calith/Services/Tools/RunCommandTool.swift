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

@Generable(description: "Arguments for running a shell command")
struct RunCommandArguments {
    @Guide(description: "The command to execute (passed to /bin/zsh -c)")
    var command: String

    @Guide(description: "Optional working directory path")
    var workingDirectory: String?
}

struct RunCommandTool: Tool {
    let description = "Runs a shell command and returns its output"

    func call(arguments: RunCommandArguments) async throws -> String {
        do {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-c", arguments.command]

            if let wd = arguments.workingDirectory {
                process.currentDirectoryURL = URL(filePath: wd)
            }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            let outString = String(data: outData, encoding: .utf8) ?? ""
            let errString = String(data: errData, encoding: .utf8) ?? ""

            var result = ""
            if !outString.isEmpty {
                result += outString
            }
            if !errString.isEmpty {
                result += "\n[stderr]\n\(errString)"
            }
            result += "\n[exit code: \(process.terminationStatus)]"

            if result.count > 50_000 {
                result = String(result.prefix(50_000)) + "\n\n[Truncated at 50,000 characters]"
            }

            return result
        } catch {
            return "Error: Could not run command — \(error.localizedDescription)"
        }
    }
}
