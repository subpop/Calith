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

@Generable(description: "Arguments for fetching a URL")
struct WebFetchArguments {
    @Guide(description: "The URL to fetch")
    var url: String
}

struct WebFetchTool: Tool {
    let description = "Fetch the content of a URL and return the response body"

    func call(arguments: WebFetchArguments) async throws -> String {
        guard let url = URL(string: arguments.url) else {
            return "Error: Invalid URL: \(arguments.url)"
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "Error: Only HTTP and HTTPS URLs are supported."
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "Error: Unexpected response type."
            }

            let statusCode = httpResponse.statusCode

            guard (200..<400).contains(statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(non-text response)"
                return "Error: HTTP \(statusCode): \(body)"
            }

            guard let body = String(data: data, encoding: .utf8) else {
                return "Error: Response body is not valid UTF-8 text (\(data.count) bytes)."
            }

            let maxLength = 100_000
            if body.count > maxLength {
                return String(body.prefix(maxLength)) + "\n\n[Truncated: response was \(body.count) characters]"
            }

            return body
        } catch {
            return "Error: Fetch failed: \(error.localizedDescription)"
        }
    }
}
