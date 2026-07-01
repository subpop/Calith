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

import AppKit
import UniformTypeIdentifiers

/// Handles `NSItemProvider` arrays from SwiftUI `.onDrop` modifiers,
/// loading file URLs and raw image data into staged attachments.
enum DropHandler {

    /// Image types in preference order for raw image data drops.
    private static let imageTypes: [(type: UTType, ext: String, mime: String)] = [
        (.png, "png", "image/png"),
        (.jpeg, "jpg", "image/jpeg"),
        (.gif, "gif", "image/gif"),
        (.webP, "webp", "image/webp"),
        (.tiff, "png", "image/png"),
    ]

    static func handleProviders(
        _ providers: [NSItemProvider],
        onAttachments: @escaping @MainActor ([StagedAttachment]) -> Void
    ) {
        for provider in providers {
            // Prefer file URL — covers Finder drags and saved files.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true),
                          url.isFileURL,
                          let fileData = try? Data(contentsOf: url)
                    else { return }

                    let staged = StagedAttachment(
                        filename: url.lastPathComponent,
                        mimeType: StagedAttachment.mimeType(for: url),
                        data: fileData
                    )
                    Task { @MainActor in onAttachments([staged]) }
                }
                continue
            }

            // Fall back to raw image data (screenshots, "Copy Image" drags).
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadDroppedImage(from: provider, onAttachments: onAttachments)
                continue
            }
        }
    }

    private static func loadDroppedImage(
        from provider: NSItemProvider,
        onAttachments: @escaping @MainActor ([StagedAttachment]) -> Void
    ) {
        guard let match = imageTypes.first(where: {
            provider.hasItemConformingToTypeIdentifier($0.type.identifier)
        }) else { return }

        provider.loadDataRepresentation(forTypeIdentifier: match.type.identifier) { data, _ in
            guard let rawData = data else { return }

            let fileData: Data
            if match.type == .tiff {
                guard let rep = NSBitmapImageRep(data: rawData),
                      let png = rep.representation(using: .png, properties: [:])
                else { return }
                fileData = png
            } else {
                fileData = rawData
            }

            let staged = StagedAttachment(
                filename: "Dropped Image.\(match.ext)",
                mimeType: match.mime,
                data: fileData
            )
            Task { @MainActor in onAttachments([staged]) }
        }
    }
}
