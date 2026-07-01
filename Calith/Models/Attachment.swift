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
final class Attachment {
    var id: UUID
    var mimeType: String
    var filename: String
    @Attribute(.externalStorage) var data: Data
    var message: Message?

    init(mimeType: String, filename: String, data: Data) {
        self.id = UUID()
        self.mimeType = mimeType
        self.filename = filename
        self.data = data
    }

    /// Whether this attachment is an image type.
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    /// Whether this attachment is a PDF.
    var isPDF: Bool {
        mimeType == "application/pdf"
    }

    /// Whether this attachment is a text-based file.
    var isText: Bool {
        mimeType.hasPrefix("text/")
    }
}
