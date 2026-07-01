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

/// Fetches available models from each LLM provider's API.
final class ModelLookupService: @unchecked Sendable {

    struct ModelInfo: Identifiable, Sendable, Hashable {
        let id: String
        let displayName: String
    }

    /// Fetches chat-capable models for the given provider.
    func fetchModels(
        for provider: LLMProvider,
        apiKey: String,
        baseURL: String
    ) async throws -> [ModelInfo] {
        let models: [ModelInfo]

        switch provider {
        case .openAI:
            models = try await fetchOpenAIModels(apiKey: apiKey, baseURL: baseURL)
        case .claude:
            models = try await fetchAnthropicModels(apiKey: apiKey, baseURL: baseURL)
        case .gemini:
            models = try await fetchGeminiModels(apiKey: apiKey, baseURL: baseURL)
        case .ollama:
            models = try await fetchOllamaModels(baseURL: baseURL)
        }

        // Sort: default model first, then alphabetical by display name.
        let defaultModel = provider.defaultModel
        return models.sorted { a, b in
            if a.id == defaultModel { return true }
            if b.id == defaultModel { return false }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    // MARK: - OpenAI

    /// Known prefixes for chat-capable OpenAI models.
    private static let openAIChatPrefixes = ["gpt-", "o1-", "o3-", "o4-", "chatgpt-"]

    private func fetchOpenAIModels(apiKey: String, baseURL: String) async throws -> [ModelInfo] {
        guard !apiKey.isEmpty else { throw ModelLookupError.missingAPIKey }

        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]]
        else { return [] }

        return dataArray.compactMap { item in
            guard let id = item["id"] as? String,
                  Self.openAIChatPrefixes.contains(where: { id.hasPrefix($0) })
            else { return nil }
            return ModelInfo(id: id, displayName: id)
        }
    }

    // MARK: - Anthropic

    private func fetchAnthropicModels(apiKey: String, baseURL: String) async throws -> [ModelInfo] {
        guard !apiKey.isEmpty else { throw ModelLookupError.missingAPIKey }

        var allModels: [ModelInfo] = []
        var afterID: String?

        while true {
            var urlString = "\(baseURL)/models?limit=100"
            if let afterID {
                urlString += "&after_id=\(afterID)"
            }

            var request = URLRequest(url: URL(string: urlString)!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]]
            else { break }

            for item in dataArray {
                guard let id = item["id"] as? String else { continue }
                let displayName = item["display_name"] as? String ?? id
                allModels.append(ModelInfo(id: id, displayName: displayName))
            }

            if json["has_more"] as? Bool == true,
               let lastID = json["last_id"] as? String
            {
                afterID = lastID
            } else {
                break
            }
        }

        return allModels
    }

    // MARK: - Gemini

    private func fetchGeminiModels(apiKey: String, baseURL: String) async throws -> [ModelInfo] {
        guard !apiKey.isEmpty else { throw ModelLookupError.missingAPIKey }

        var allModels: [ModelInfo] = []
        var pageToken: String?

        while true {
            var urlString = "\(baseURL)/models?key=\(apiKey)&pageSize=100"
            if let pageToken {
                urlString += "&pageToken=\(pageToken)"
            }

            let request = URLRequest(url: URL(string: urlString)!)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]]
            else { break }

            for item in models {
                // Only include models that support generateContent.
                guard let methods = item["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent"),
                      let name = item["name"] as? String
                else { continue }

                let id = name.replacing("models/", with: "")
                let displayName = item["displayName"] as? String ?? id
                allModels.append(ModelInfo(id: id, displayName: displayName))
            }

            if let nextToken = json["nextPageToken"] as? String, !nextToken.isEmpty {
                pageToken = nextToken
            } else {
                break
            }
        }

        return allModels
    }

    // MARK: - Ollama

    private func fetchOllamaModels(baseURL: String) async throws -> [ModelInfo] {
        let request = URLRequest(url: URL(string: "\(baseURL)/api/tags")!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }

        return models.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return ModelInfo(id: name, displayName: name)
        }
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelLookupError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ModelLookupError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

enum ModelLookupError: LocalizedError {
    case missingAPIKey
    case httpError(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key is required to fetch models"
        case .httpError(let code): "Failed to fetch models (HTTP \(code))"
        case .invalidResponse: "Invalid response from server"
        }
    }
}
