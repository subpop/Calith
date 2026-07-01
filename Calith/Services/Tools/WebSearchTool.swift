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

@Generable(description: "Arguments for searching the web")
struct WebSearchArguments {
    @Guide(description: "The search query to execute")
    var query: String
}

struct WebSearchTool: Tool {
    let description = "Search the web for information using a query. Returns relevant results with titles, URLs, and content snippets."

    func call(arguments: WebSearchArguments) async throws -> String {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: Search query must not be empty."
        }

        guard let apiKey = Secrets.tavilyAPIKey, !apiKey.isEmpty else {
            return "Error: No Tavily API key configured. Set TAVILY_API_KEY in Secrets.xcconfig and rebuild."
        }

        let body: [String: Any] = [
            "query": arguments.query,
            "include_answer": true,
            "max_results": 5,
        ]

        guard let url = URL(string: "https://api.tavily.com/search") else {
            return "Error: Internal error: invalid Tavily API URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return "Error: Failed to encode request: \(error.localizedDescription)"
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "Error: Unexpected response type."
            }

            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401:
                return "Error: Tavily API key is invalid or missing."
            case 429:
                return "Error: Tavily rate limit exceeded. Please try again later."
            case 432:
                return "Error: Tavily API credit limit exceeded."
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "(no response body)"
                return "Error: Tavily API error (HTTP \(httpResponse.statusCode)): \(errorBody)"
            }

            return formatResults(data: data)
        } catch {
            return "Error: Search failed: \(error.localizedDescription)"
        }
    }

    private func formatResults(data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: Failed to parse Tavily response."
        }

        var output = ""

        if let answer = json["answer"] as? String, !answer.isEmpty {
            output += "## Answer\n\n\(answer)\n\n"
        }

        if let results = json["results"] as? [[String: Any]], !results.isEmpty {
            output += "## Search Results\n\n"

            for (index, result) in results.enumerated() {
                let title = result["title"] as? String ?? "Untitled"
                let url = result["url"] as? String ?? ""
                let content = result["content"] as? String ?? ""

                output += "### \(index + 1). \(title)\n"
                if !url.isEmpty {
                    output += "URL: \(url)\n"
                }
                if !content.isEmpty {
                    output += "\(content)\n"
                }
                output += "\n"
            }
        } else {
            output += "No results found.\n"
        }

        let maxLength = 100_000
        if output.count > maxLength {
            return String(output.prefix(maxLength)) + "\n\n[Truncated: response was \(output.count) characters]"
        }

        return output
    }
}
