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
import SwiftData

@Model
final class Memory {
    var id: UUID
    var fact: String
    var category: String
    var createdAt: Date
    var source: String
    var embedding: Data?

    init(
        fact: String,
        category: String,
        createdAt: Date = .now,
        source: String
    ) {
        self.id = UUID()
        self.fact = fact
        self.category = category
        self.createdAt = createdAt
        self.source = source
    }
}
