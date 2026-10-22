import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Seção de anexos reutilizada em tarefas e sub-itens.
/// Suporta seletor de arquivos, colar da área de transferência e arrastar-e-soltar.
struct AttachmentsSection: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var attachments: [Attachment]

    @State private var isTargeted = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Anexos", systemImage: "paperclip")
                if !attachments.isEmpty {
                    Text("\(attachments.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Arquivo…", systemImage: "folder", action: chooseFiles)
                Button("Colar", systemImage: "doc.on.clipboard", action: pasteFromClipboard)
            }
            .controlSize(.small)

            Group {
                if attachments.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(attachments) { attachment in
                            AttachmentTile(attachment: attachment)
                                .onTapGesture(count: 2) { store.open(attachment) }
                                .contextMenu {
                                    Button("Abrir") { store.open(attachment) }
                                    Button("Mostrar no Finder") { store.revealInFinder(attachment) }
                                    Divider()
                                    Button("Remover", role: .destructive) { remove(attachment) }
                                }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: attachments.isEmpty ? [5] : [])
                    )
            )
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted, perform: handleDrop)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Solte arquivos ou imagens aqui")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("ou use Arquivo… / Colar (⌘V)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Ações

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Anexar arquivos"
        panel.prompt = "Anexar"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addFile)
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            urls.forEach(addFile)
            return
        }
        if let image = NSImage(pasteboard: pasteboard), let png = image.pngData() {
            addData(png, fileExtension: "png")
            return
        }
        errorMessage = "A área de transferência não contém arquivo nem imagem."
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    }
                    guard let url else { return }
                    DispatchQueue.main.async { addFile(url) }
                }
            } else if let typeID = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) {
                handled = true
                let ext = UTType(typeID)?.preferredFilenameExtension ?? "png"
                provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { addData(data, fileExtension: ext) }
                }
            }
        }
        return handled
    }

    private func addFile(_ url: URL) {
        do {
            attachments.append(try store.importFile(from: url))
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível anexar \(url.lastPathComponent)."
        }
    }

    private func addData(_ data: Data, fileExtension: String) {
        do {
            attachments.append(try store.importData(data, fileExtension: fileExtension))
            errorMessage = nil
        } catch {
            errorMessage = "Não foi possível salvar a imagem."
        }
    }

    private func remove(_ attachment: Attachment) {
        store.deleteFile(attachment)
        attachments.removeAll { $0.id == attachment.id }
    }
}

// MARK: - Miniatura

private struct AttachmentTile: View {
    @EnvironmentObject private var store: TaskStore
    let attachment: Attachment
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: attachment.isImage ? .fill : .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))

            Text(attachment.displayName)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 84)
        }
        .help(attachment.displayName)
        .task(id: attachment.id) { thumbnail = await loadThumbnail() }
    }

    private func loadThumbnail() async -> NSImage {
        let url = store.fileURL(for: attachment)
        let isImage = attachment.isImage
        return await Task.detached(priority: .utility) {
            if isImage, let image = NSImage(contentsOf: url) {
                return image.downsampled(maxDimension: 144)
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }.value
    }
}

// MARK: - Utilitários de imagem

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Reduz a imagem para caber em `maxDimension`, preservando a proporção.
    func downsampled(maxDimension: CGFloat) -> NSImage {
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: target)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: target),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
