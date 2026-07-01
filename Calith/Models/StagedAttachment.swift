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
import UniformTypeIdentifiers

/// A lightweight value type representing a staged attachment before it is persisted.
struct StagedAttachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data

    /// Creates an ``Attachment`` model object from this staged value.
    func toAttachment() -> Attachment {
        Attachment(mimeType: mimeType, filename: filename, data: data)
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isPDF: Bool { mimeType == "application/pdf" }

    /// UTTypes accepted for drag-and-drop.
    static let dropTypes: [UTType] = [.fileURL, .image]

    /// Derives a MIME type from a file URL's extension.
    nonisolated static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            if utType.conforms(to: .image) {
                return utType.preferredMIMEType ?? "image/png"
            } else if utType.conforms(to: .pdf) {
                return "application/pdf"
            } else {
                return utType.preferredMIMEType ?? "text/plain"
            }
        }
        return "application/octet-stream"
    }
}
