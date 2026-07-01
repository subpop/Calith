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

/// Generates human-readable summaries and permission questions from tool names and JSON arguments.
struct ToolDescription {

    /// A one-line summary of what the tool did, e.g. "Read the file ~/TODO.txt".
    static func summary(toolName: String, arguments: String?) throws -> AttributedString {
        let args = parseArguments(arguments)

        switch toolName {
        case "WebSearch":
            let query = args["query"] ?? "the web"
            return try AttributedString(markdown: "Searched the web for \"\(query)\"")
        case "ReadFile":
            let path = abbreviatedPath(args["path"] ?? "a file")
            return try AttributedString(markdown: "Read the file **\(path)**")
        case "WriteFile":
            let path = abbreviatedPath(args["path"] ?? "a file")
            return try AttributedString(markdown: "Wrote to the file **\(path)**")
        case "RunCommand":
            let command = args["command"] ?? "a command"
            var result = AttributedString("Ran command:\n\n")
            result.append(try AttributedString(markdown: "`\(command)`"))
            return result
        case "ListDirectory":
            let path = abbreviatedPath(args["path"] ?? "a directory")
            return try AttributedString(markdown: "Listed the directory **\(path)**")
        case "RunAppleScript":
            return try AttributedString(markdown: "Ran AppleScript")
        case "WebFetch":
            let url = args["url"] ?? "a URL"
            return try AttributedString(markdown: "Fetched \(url)")
        default:
            return try AttributedString(markdown: "Ran \(toolName)")
        }
    }

    /// A conversational question asking the user for permission, e.g. "May I read the file ~/TODO.txt?"
    static func permissionQuestion(toolName: String, arguments: String?) throws -> AttributedString {
        let args = parseArguments(arguments)

        switch toolName {
        case "WebSearch":
            let query = args["query"] ?? "the web"
            return try AttributedString(markdown:"May I search the web for \"\(query)\"?")
        case "ReadFile":
            let path = abbreviatedPath(args["path"] ?? "a file")
            return try AttributedString(markdown: "May I read the file **\(path)**?")
        case "WriteFile":
            let path = abbreviatedPath(args["path"] ?? "a file")
            return try AttributedString(markdown: "May I write to the file **\(path)**?")
        case "RunCommand":
            let command = args["command"] ?? "a command"
            var result = AttributedString("May I run the following command?\n\n")
            result.append(try AttributedString(markdown: "`\(command)`"))
            return result
        case "ListDirectory":
            let path = abbreviatedPath(args["path"] ?? "a directory")
            return try AttributedString(markdown: "May I list the directory **\(path)**?")
        case "RunAppleScript":
            return try AttributedString(markdown: "May I run this AppleScript?")
        case "WebFetch":
            let url = args["url"] ?? "a URL"
            return try AttributedString(markdown: "May I fetch the URL \(url)?")
        default:
            return try AttributedString(markdown: "May I run \(toolName)?")
        }
    }

    /// SF Symbol name for a given tool.
    static func iconName(for toolName: String) -> String {
        switch toolName {
        case "RunCommand": "terminal"
        case "RunAppleScript": "applescript"
        case "ReadFile": "doc.text"
        case "WriteFile": "doc.badge.plus"
        case "ListDirectory": "folder"
        case "WebFetch": "globe"
        case "WebSearch": "magnifyingglass"
        default: "wrench"
        }
    }

    // MARK: - Private

    /// Parses a JSON arguments string into a flat string dictionary, extracting only string values.
    private static func parseArguments(_ arguments: String?) -> [String: String] {
        guard let arguments, !arguments.isEmpty,
              let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [String: String] = [:]
        for (key, value) in json {
            if let str = value as? String {
                result[key] = str
            }
        }
        return result
    }

    /// Replaces the current user's home directory prefix with `~/`.
    private static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        if path.hasPrefix(home) {
            return "~/" + path.dropFirst(home.count)
                .drop(while: { $0 == "/" })
        }
        return path
    }
}
