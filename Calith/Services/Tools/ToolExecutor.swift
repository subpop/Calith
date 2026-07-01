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

/// Per-tool confirmation policy.
enum ToolConfirmationPolicy: String, CaseIterable, Sendable, Codable {
    case alwaysAsk = "Always Ask"
    case alwaysRun = "Always Run"
}

/// Manages tool execution, confirmation flow, and JSON-schema definitions for the OpenAI backend.
@Observable
final class ToolExecutor {
    /// Per-tool confirmation policies. RunCommand and RunAppleScript default to "ask".
    var policies: [String: ToolConfirmationPolicy] = [
        "ReadFile": .alwaysRun,
        "WriteFile": .alwaysRun,
        "RunCommand": .alwaysAsk,
        "ListDirectory": .alwaysRun,
        "RunAppleScript": .alwaysAsk,
        "WebFetch": .alwaysRun,
        "WebSearch": .alwaysRun,
    ]

    /// Currently pending confirmation — set when a tool call needs user approval.
    var pendingConfirmation: PendingToolCall?

    struct PendingToolCall: Sendable {
        let id: String
        let name: String
        let arguments: String
    }

    // MARK: - Tool instances

    private let readFile = ReadFileTool()
    private let writeFile = WriteFileTool()
    private let runCommand = RunCommandTool()
    private let listDirectory = ListDirectoryTool()
    private let runAppleScript = RunAppleScriptTool()
    private let webFetch = WebFetchTool()
    private let webSearch = WebSearchTool()

    // MARK: - Foundation Models tools

    /// All tools as Foundation Models `Tool` protocol instances for the on-device backend.
    var foundationModelTools: [any Tool] {
        var tools: [any Tool] = [readFile, writeFile, runCommand, listDirectory, runAppleScript, webFetch]
        if let key = Secrets.tavilyAPIKey, !key.isEmpty {
            tools.append(webSearch)
        }
        return tools
    }

    // MARK: - OpenAI tool definitions

    /// Tool definitions as `ToolDefinition` structs for the OpenAI backend.
    var openAIToolDefinitions: [ToolDefinition] {
        var defs: [ToolDefinition] = [
            ToolDefinition(
                name: "ReadFile",
                description: "Reads the contents of a file at the given path",
                parametersSchema: """
                {"type":"object","properties":{"path":{"type":"string","description":"The absolute path to the file to read"}},"required":["path"],"additionalProperties":false}
                """
            ),
            ToolDefinition(
                name: "WriteFile",
                description: "Writes text content to a file at the given path, creating it if needed",
                parametersSchema: """
                {"type":"object","properties":{"path":{"type":"string","description":"The absolute path to the file to write"},"content":{"type":"string","description":"The text content to write to the file"}},"required":["path","content"],"additionalProperties":false}
                """
            ),
            ToolDefinition(
                name: "RunCommand",
                description: "Runs a shell command and returns its output",
                parametersSchema: """
                {"type":"object","properties":{"command":{"type":"string","description":"The command to execute (passed to /bin/zsh -c)"},"workingDirectory":{"type":"string","description":"Optional working directory path"}},"required":["command"],"additionalProperties":false}
                """
            ),
            ToolDefinition(
                name: "ListDirectory",
                description: "Lists the contents of a directory",
                parametersSchema: """
                {"type":"object","properties":{"path":{"type":"string","description":"The absolute path to the directory to list"},"showHidden":{"type":"boolean","description":"Whether to include hidden files (defaults to false)"}},"required":["path"],"additionalProperties":false}
                """
            ),
            ToolDefinition(
                name: "RunAppleScript",
                description: "Executes AppleScript code and returns the result",
                parametersSchema: """
                {"type":"object","properties":{"source":{"type":"string","description":"The AppleScript source code to execute"}},"required":["source"],"additionalProperties":false}
                """
            ),
            ToolDefinition(
                name: "WebFetch",
                description: "Fetch the content of a URL and return the response body",
                parametersSchema: """
                {"type":"object","properties":{"url":{"type":"string","description":"The URL to fetch"}},"required":["url"],"additionalProperties":false}
                """
            ),
        ]

        if let key = Secrets.tavilyAPIKey, !key.isEmpty {
            defs.append(ToolDefinition(
                name: "WebSearch",
                description: "Search the web for information using a query. Returns relevant results with titles, URLs, and content snippets.",
                parametersSchema: """
                {"type":"object","properties":{"query":{"type":"string","description":"The search query to execute"}},"required":["query"],"additionalProperties":false}
                """
            ))
        }

        return defs
    }

    // MARK: - Execution

    /// Whether the given tool requires user confirmation.
    /// Reads from UserDefaults (synced with @AppStorage in Settings) with fallback to in-memory policies.
    func requiresConfirmation(_ toolName: String) -> Bool {
        let key = "tool.\(toolName)"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored == ToolConfirmationPolicy.alwaysAsk.rawValue
        }
        return policies[toolName] == .alwaysAsk
    }

    /// Executes a tool call by name with JSON arguments string. Used by the OpenAI backend path.
    func execute(name: String, arguments: String) async -> String {
        do {
            let data = Data(arguments.utf8)

            switch name {
            case "ReadFile":
                let args = try JSONDecoder().decode(ReadFileJSONArgs.self, from: data)
                return try await readFile.call(arguments: ReadFileArguments(path: args.path))

            case "WriteFile":
                let args = try JSONDecoder().decode(WriteFileJSONArgs.self, from: data)
                return try await writeFile.call(arguments: WriteFileArguments(path: args.path, content: args.content))

            case "RunCommand":
                let args = try JSONDecoder().decode(RunCommandJSONArgs.self, from: data)
                return try await runCommand.call(arguments: RunCommandArguments(command: args.command, workingDirectory: args.workingDirectory))

            case "ListDirectory":
                let args = try JSONDecoder().decode(ListDirectoryJSONArgs.self, from: data)
                return try await listDirectory.call(arguments: ListDirectoryArguments(path: args.path, showHidden: args.showHidden))

            case "RunAppleScript":
                let args = try JSONDecoder().decode(RunAppleScriptJSONArgs.self, from: data)
                return try await runAppleScript.call(arguments: RunAppleScriptArguments(source: args.source))

            case "WebFetch":
                let args = try JSONDecoder().decode(WebFetchJSONArgs.self, from: data)
                return try await webFetch.call(arguments: WebFetchArguments(url: args.url))

            case "WebSearch":
                let args = try JSONDecoder().decode(WebSearchJSONArgs.self, from: data)
                return try await webSearch.call(arguments: WebSearchArguments(query: args.query))

            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            return "Tool error: \(error.localizedDescription)"
        }
    }
}

// MARK: - JSON argument types for OpenAI backend decoding

private struct ReadFileJSONArgs: Decodable {
    let path: String
}

private struct WriteFileJSONArgs: Decodable {
    let path: String
    let content: String
}

private struct RunCommandJSONArgs: Decodable {
    let command: String
    let workingDirectory: String?
}

private struct ListDirectoryJSONArgs: Decodable {
    let path: String
    let showHidden: Bool?
}

private struct RunAppleScriptJSONArgs: Decodable {
    let source: String
}

private struct WebFetchJSONArgs: Decodable {
    let url: String
}

private struct WebSearchJSONArgs: Decodable {
    let query: String
}
