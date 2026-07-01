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
import NaturalLanguage

final class EmbeddingService: Sendable {
    private let model: NLEmbedding?

    init() {
        self.model = NLEmbedding.sentenceEmbedding(for: .english)
    }

    func embed(_ text: String) -> [Float]? {
        guard let model, let vector = model.vector(for: text) else { return nil }
        return vector.map(Float.init)
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).map { $0 * $1 }.reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    func topK(query: String, among memories: [Memory], k: Int = 15) -> [Memory] {
        guard let queryVector = embed(query) else {
            return Array(memories.prefix(k))
        }

        let scored: [(Memory, Float)] = memories.compactMap { memory in
            guard let data = memory.embedding,
                  let vector = deserialize(data)
            else { return nil }
            return (memory, cosineSimilarity(queryVector, vector))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { $0.0 }
    }

    func serialize(_ vector: [Float]) -> Data {
        Data(bytes: vector, count: vector.count * MemoryLayout<Float>.size)
    }

    func deserialize(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
