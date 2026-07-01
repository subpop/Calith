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

import SwiftUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    var isAnimating: Bool
    var attachmentsEnabled: Bool
    @Binding var attachments: [StagedAttachment]
    var onSend: (String, [StagedAttachment]) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @State private var showingFilePicker = false
    @State private var gradientAngle: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var pasteHandler = PasteHandler()
    @FocusState private var isFocused: Bool

    private let rainbowColors: [Color] = [.red, .purple, .teal, .purple, .red]
    private let shape = RoundedRectangle(cornerRadius: 12)

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                AttachmentPreviewStrip(attachments: $attachments)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                if attachmentsEnabled && !isAnimating {
                    Button("Attach", systemImage: "plus.circle.fill", action: { showingFilePicker = true })
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .focused($isFocused)
                    .onSubmit(send)
                    .disabled(isAnimating)

                if isAnimating {
                    Button("Cancel", systemImage: "stop.circle.fill", action: onCancel)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .buttonStyle(.borderless)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: shape)
        .overlay {
            let gradient = AngularGradient(
                colors: rainbowColors,
                center: .center,
                angle: .degrees(gradientAngle)
            )
            shape
                .stroke(gradient, lineWidth: 2.0)
                .blur(radius: 5.0)
                .shadow(color: .red.opacity(0.4), radius: 20)
                .shadow(color: .purple.opacity(0.4), radius: 20)
                .shadow(color: .teal.opacity(0.3), radius: 20)
                .opacity(glowOpacity)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image, .pdf, .plainText, .sourceCode, .json, .xml, .yaml],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onAppear {
            isFocused = true
            pasteHandler.startMonitoring()
            if isAnimating { startAnimation() }
        }
        .onDisappear {
            pasteHandler.stopMonitoring()
        }
        .onChange(of: pasteHandler.pastedAttachments) { _, staged in
            guard attachmentsEnabled, let staged else { return }
            pasteHandler.pastedAttachments = nil
            attachments.append(contentsOf: staged)
        }
        .onChange(of: isAnimating) { _, animating in
            if animating {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    // MARK: - Send

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        onSend(trimmed, attachments)
        text = ""
        attachments = []
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = StagedAttachment.mimeType(for: url)
            attachments.append(StagedAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        glowOpacity = 1.0
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            gradientAngle += 360
        }
    }

    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.6)) {
            glowOpacity = 0
        }
        withAnimation(.default) {
            gradientAngle = 0
        }
    }
}

// MARK: - Attachment Preview Strip

private struct AttachmentPreviewStrip: View {
    @Binding var attachments: [StagedAttachment]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment) {
                        withAnimation {
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
    }
}

private struct AttachmentThumbnail: View {
    let attachment: StagedAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: attachment.isPDF ? "doc.richtext" : "doc.text")
                            .font(.title3)
                        Text(attachment.filename)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(width: 56, height: 56)
                    .background(.fill.quinary, in: .rect(cornerRadius: 8))
                }
            }

            Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .offset(x: 4, y: -4)
        }
    }
}

#Preview("Ready") {
    @Previewable @State var attachments: [StagedAttachment] = []
    MessageInputView(isAnimating: false, attachmentsEnabled: true, attachments: $attachments) { message, attachments in
        print(message, attachments.count)
    } onCancel: {}
    .padding()
}

#Preview("Animating") {
    @Previewable @State var attachments: [StagedAttachment] = []
    MessageInputView(isAnimating: true, attachmentsEnabled: true, attachments: $attachments) { message, attachments in
        print(message, attachments.count)
    } onCancel: {}
    .padding()
}

#Preview("No Attachments (Apple Intelligence)") {
    @Previewable @State var attachments: [StagedAttachment] = []
    MessageInputView(isAnimating: false, attachmentsEnabled: false, attachments: $attachments) { message, attachments in
        print(message, attachments.count)
    } onCancel: {}
    .padding()
}

