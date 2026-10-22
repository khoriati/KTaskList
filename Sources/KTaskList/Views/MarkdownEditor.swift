import AppKit
import SwiftUI

/// Editor WYSIWYG cujo modelo é Markdown: renderiza ao carregar/colar e
/// serializa de volta para Markdown a cada alteração.
struct MarkdownEditor: View {
    @Binding var markdown: String
    var placeholder = "Descrição, links, contexto…"
    var minHeight: CGFloat = 110
    var maxHeight: CGFloat = 320

    @StateObject private var controller = MarkdownEditorController()
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            MarkdownTextViewRepresentable(markdown: $markdown, controller: controller, contentHeight: $contentHeight)
                .frame(height: min(max(contentHeight + 16, minHeight), maxHeight))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .overlay(alignment: .topLeading) {
                    if markdown.isEmpty && !controller.hasText {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            toolButton("bold", "Negrito (⌘B)", active: controller.state.bold) { controller.toggleBold() }
            toolButton("italic", "Itálico (⌘I)", active: controller.state.italic) { controller.toggleItalic() }
            toolButton("strikethrough", "Tachado (⌘⇧X)", active: controller.state.strike) { controller.toggleStrike() }
            toolButton("chevron.left.forwardslash.chevron.right", "Código (⌘E)", active: controller.state.code) { controller.toggleCode() }
            Divider().frame(height: 14).padding(.horizontal, 3)
            Menu {
                Button("Parágrafo") { controller.setBlock(.paragraph) }
                Button("Título 1") { controller.setBlock(.heading1) }
                Button("Título 2") { controller.setBlock(.heading2) }
                Button("Título 3") { controller.setBlock(.heading3) }
                Button("Citação") { controller.setBlock(.quote) }
                Button("Bloco de código") { controller.setBlock(.codeBlock) }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Estilo do parágrafo")
            toolButton("list.bullet", "Lista", active: controller.state.list == .bullet) { controller.toggleList(ordered: false) }
            toolButton("list.number", "Lista numerada", active: controller.state.list == .ordered) { controller.toggleList(ordered: true) }
            toolButton("link", "Link", active: controller.state.link) { controller.insertLink() }
            Spacer()
            Text("Markdown")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .help("As notas são salvas em Markdown; colar Markdown renderiza na hora.")
        }
        .controlSize(.small)
    }

    private func toolButton(_ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(active ? Color.accentColor.opacity(0.25) : Color.clear))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Controlador

/// Ponte entre a barra de ferramentas SwiftUI e o NSTextView.
@MainActor
final class MarkdownEditorController: ObservableObject {
    enum ListKind { case none, bullet, ordered }
    struct SelectionState: Equatable {
        var bold = false, italic = false, strike = false, code = false, link = false
        var block: MarkdownBlock = .paragraph
        var list: ListKind = .none
    }

    @Published var state = SelectionState()
    @Published var hasText = false
    weak var textView: MarkdownTextView?

    func refreshState() {
        guard let textView else { return }
        let attrs = textView.selectedRange().length > 0
            ? textView.textStorage?.attributes(at: textView.selectedRange().location, effectiveRange: nil) ?? [:]
            : textView.typingAttributes
        let font = attrs[.font] as? NSFont
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let new = SelectionState(
            bold: traits.contains(.boldFontMask),
            italic: traits.contains(.italicFontMask),
            strike: (attrs[.strikethroughStyle] as? Int ?? 0) != 0,
            code: attrs[.mdCode] as? Bool ?? false,
            link: attrs[.link] != nil,
            block: MarkdownBlock(rawValue: attrs[.mdBlock] as? String ?? "") ?? .paragraph,
            list: lists.isEmpty ? .none : (lists.last?.markerFormat == .decimal ? .ordered : .bullet)
        )
        if new != state { state = new }
        let nonEmpty = (textView.string.isEmpty == false)
        if nonEmpty != hasText { hasText = nonEmpty }
    }

    func toggleBold() { textView?.toggleInline(.bold) }
    func toggleItalic() { textView?.toggleInline(.italic) }
    func toggleStrike() { textView?.toggleInline(.strike) }
    func toggleCode() { textView?.toggleInline(.code) }
    func setBlock(_ block: MarkdownBlock) { textView?.setBlock(block) }
    func toggleList(ordered: Bool) { textView?.toggleList(ordered: ordered) }
    func insertLink() { textView?.promptLink() }
}

// MARK: - NSViewRepresentable

private struct MarkdownTextViewRepresentable: NSViewRepresentable {
    @Binding var markdown: String
    let controller: MarkdownEditorController
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.font = MarkdownTheme.body
        textView.typingAttributes = MarkdownTheme.typingAttributes
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.onContentChanged = { [weak controller] in controller?.refreshState() }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        controller.textView = textView
        context.coordinator.textView = textView
        context.coordinator.load(markdown)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // Só recarrega quando o Markdown mudou por fora (não pelo próprio editor).
        if markdown != context.coordinator.lastSerialized {
            context.coordinator.load(markdown)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextViewRepresentable
        weak var textView: MarkdownTextView?
        var lastSerialized = ""

        init(_ parent: MarkdownTextViewRepresentable) { self.parent = parent }

        func load(_ markdown: String) {
            guard let textView else { return }
            lastSerialized = markdown
            let attributed = MarkdownConverter.attributedString(fromMarkdown: markdown)
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = MarkdownTheme.typingAttributes
            updateHeight()
            parent.controller.refreshState()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage else { return }
            let serialized = MarkdownConverter.markdown(from: storage)
            lastSerialized = serialized
            if parent.markdown != serialized { parent.markdown = serialized }
            updateHeight()
            parent.controller.refreshState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.refreshState()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            // Só esquemas web/e-mail: Markdown colado de terceiros não pode abrir
            // file:// nem esquemas de outros apps ao clicar.
            guard let url, MarkdownTextView.isAllowedLink(url) else { return true }
            NSWorkspace.shared.open(url)
            return true
        }

        private func updateHeight() {
            guard let textView else { return }
            textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
            let height = textView.textLayoutManager?.usageBoundsForTextContainer.height ?? 0
            let total = height + textView.textContainerInset.height * 2
            if abs(total - parent.contentHeight) > 0.5 {
                DispatchQueue.main.async { self.parent.contentHeight = total }
            }
        }
    }
}

// MARK: - Regras de entrada

/// Padrões reconhecidos enquanto o usuário digita.
enum MarkdownInputRule {
    /// `# `, `## `, `### `, `- `, `* `, `+ `, `1. `, `> ` no início da linha.
    static let blockPrefix = #/(#{1,3}|[-*+]|\d{1,3}\.|>) /#

    struct Inline {
        let trigger: String
        let pattern: Regex<(Substring, Substring)>
        let style: MarkdownTextView.InlineStyle

        func apply(to attrs: [NSAttributedString.Key: Any], block: MarkdownBlock) -> [NSAttributedString.Key: Any] {
            MarkdownInputRule.set(style, on: attrs, block: block, enabled: true)
        }
    }

    static let inlineRules: [Inline] = [
        Inline(trigger: "*", pattern: #/\*\*([^*]+)\*\*$/#, style: .bold),
        Inline(trigger: "*", pattern: #/\*([^*]+)\*$/#, style: .italic),
        Inline(trigger: "`", pattern: #/`([^`]+)`$/#, style: .code),
        Inline(trigger: "~", pattern: #/~~([^~]+)~~$/#, style: .strike),
    ]

    static func clear(_ rule: Inline, from attrs: [NSAttributedString.Key: Any], block: MarkdownBlock) -> [NSAttributedString.Key: Any] {
        set(rule.style, on: attrs, block: block, enabled: false)
    }

    private static func set(_ style: MarkdownTextView.InlineStyle, on attrs: [NSAttributedString.Key: Any],
                            block: MarkdownBlock, enabled: Bool) -> [NSAttributedString.Key: Any] {
        var attrs = attrs
        let font = attrs[.font] as? NSFont ?? MarkdownTheme.body
        let traits = NSFontManager.shared.traits(of: font)
        switch style {
        case .bold, .italic:
            let mask: NSFontTraitMask = style == .bold ? .boldFontMask : .italicFontMask
            attrs[.font] = enabled
                ? NSFontManager.shared.convert(font, toHaveTrait: mask)
                : NSFontManager.shared.convert(font, toNotHaveTrait: mask)
        case .strike:
            attrs[.strikethroughStyle] = enabled ? NSUnderlineStyle.single.rawValue : 0
        case .code:
            if enabled {
                attrs[.mdCode] = true
                attrs[.backgroundColor] = MarkdownTheme.codeBackground
                attrs[.font] = MarkdownTheme.font(for: block, code: true)
            } else {
                attrs.removeValue(forKey: .mdCode)
                attrs.removeValue(forKey: .backgroundColor)
                attrs[.font] = MarkdownTheme.font(for: block, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask))
            }
        }
        return attrs
    }
}

// MARK: - NSTextView

/// NSTextView com atalhos, colagem de Markdown e comportamento de blocos.
final class MarkdownTextView: NSTextView {
    enum InlineStyle { case bold, italic, strike, code }

    /// Esquemas de link aceitos ao inserir e ao clicar.
    static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    static func isAllowedLink(_ url: URL) -> Bool {
        url.scheme.map { allowedLinkSchemes.contains($0.lowercased()) } ?? false
    }

    var onContentChanged: (() -> Void)?

    /// Atributos de parágrafo a aplicar ao próximo texto digitado. Necessário
    /// porque o NSTextView descarta `textLists` dos atributos de digitação em
    /// parágrafos ainda vazios.
    private var pendingParagraphAttributes: [NSAttributedString.Key: Any]?
    /// Acabou de abrir um bloco com ```: o próximo Enter fica dentro do bloco.
    private var justOpenedCodeFence = false

    // MARK: Colagem

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), MarkdownConverter.looksLikeMarkdown(text) {
            let attributed = MarkdownConverter.attributedString(fromMarkdown: text)
            insertText(attributed, replacementRange: selectedRange())
            didChangeText()
            return
        }
        pasteAsPlainText(sender)
    }

    // MARK: Atalhos

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "b": toggleInline(.bold); return
            case "i": toggleInline(.italic); return
            case "e": toggleInline(.code); return
            default: break
            }
        } else if flags == [.command, .shift], key == "x" {
            toggleInline(.strike); return
        }
        super.keyDown(with: event)
    }

    // MARK: Enter em títulos e listas

    override func insertNewline(_ sender: Any?) {
        let paragraph = paragraphRange(at: selectedRange().location)
        let attrs = attributes(atParagraph: paragraph)
        let block = MarkdownBlock(rawValue: attrs[.mdBlock] as? String ?? "") ?? .paragraph
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let paragraphText = (string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)

        if justOpenedCodeFence {
            // ``` + Enter: começa a digitar dentro do bloco de código.
            justOpenedCodeFence = false
            return
        }
        // Enter em item de lista vazio (ou linha vazia de bloco de código) encerra o bloco.
        if paragraphText.isEmpty, !lists.isEmpty || block == .codeBlock {
            applyParagraph(.paragraph, lists: [], to: paragraph)
            return
        }
        pendingParagraphAttributes = nil
        super.insertNewline(sender)
        // Títulos e citações não continuam na linha seguinte.
        if block.headingLevel != nil || block == .quote {
            typingAttributes = MarkdownTheme.typingAttributes
            let newParagraph = paragraphRange(at: selectedRange().location)
            applyParagraph(.paragraph, lists: [], to: newParagraph)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onContentChanged?()
    }

    // MARK: Regras de entrada (estilo Typora)

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        applyPendingParagraphAttributes()
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        guard typed.count == 1 else { return }
        applyInputRules(afterTyping: typed)
    }

    private func applyPendingParagraphAttributes() {
        justOpenedCodeFence = false
        guard let pending = pendingParagraphAttributes, let storage = textStorage, storage.length > 0 else { return }
        pendingParagraphAttributes = nil
        let paragraph = paragraphRange(at: max(0, selectedRange().location - 1))
        guard paragraph.length > 0 else { return }
        storage.addAttributes(pending, range: paragraph)
        var typing = typingAttributes
        for (key, value) in pending { typing[key] = value }
        typingAttributes = typing
    }

    /// Converte marcação digitada no início da linha (`# `, `- `, `1. `, `> `, ```` ``` ````)
    /// e marcação inline concluída (`**x**`, `*x*`, `` `x` ``, `~~x~~`).
    private func applyInputRules(afterTyping typed: String) {
        guard let storage = textStorage else { return }
        let caret = selectedRange().location
        let paragraph = paragraphRange(at: max(0, caret - 1))
        guard caret >= paragraph.location else { return }
        let ns = string as NSString
        let beforeRange = NSRange(location: paragraph.location, length: caret - paragraph.location)
        let before = ns.substring(with: beforeRange)
        let attrs = attributes(atParagraph: paragraph)
        let block = MarkdownBlock(rawValue: attrs[.mdBlock] as? String ?? "") ?? .paragraph

        // Cerca de código: ``` sozinho na linha vira bloco de código.
        if typed == "`", before == "```" {
            replace(beforeRange, with: NSAttributedString(string: ""))
            applyParagraph(.codeBlock, lists: [], to: NSRange(location: paragraph.location, length: 0))
            justOpenedCodeFence = true
            return
        }
        guard block != .codeBlock else { return }

        if typed == " ", let match = before.wholeMatch(of: MarkdownInputRule.blockPrefix) {
            let prefix = String(match.1)
            replace(beforeRange, with: NSAttributedString(string: ""))
            let target = NSRange(location: paragraph.location, length: 0)
            switch prefix {
            case "-", "*", "+":
                applyParagraph(.paragraph, lists: [NSTextList(markerFormat: .disc, options: 0)], to: target)
            case ">":
                applyParagraph(.quote, lists: [], to: target)
            case _ where prefix.hasPrefix("#"):
                applyParagraph(.heading(prefix.count), lists: [], to: target)
            default:
                applyParagraph(.paragraph, lists: [NSTextList(markerFormat: .decimal, options: 0)], to: target)
            }
            return
        }

        guard "*`~".contains(typed) else { return }
        for rule in MarkdownInputRule.inlineRules where rule.trigger == typed {
            guard let match = before.firstMatch(of: rule.pattern) else { continue }
            let inner = String(match.1)
            guard !inner.isEmpty, !inner.hasPrefix(" "), !inner.hasSuffix(" ") else { continue }
            // Marcador precedido de `*` ou `\` não conta (evita confundir com negrito/escape).
            if match.range.lowerBound > before.startIndex,
               "*\\".contains(before[before.index(before: match.range.lowerBound)]) { continue }
            let matchRange = NSRange(match.range, in: before)
            let absolute = NSRange(location: paragraph.location + matchRange.location, length: matchRange.length)
            var styled = storage.attributes(at: absolute.location, effectiveRange: nil)
            styled = rule.apply(to: styled, block: block)
            replace(absolute, with: NSAttributedString(string: inner, attributes: styled))
            // Depois do marcador de fechamento, volta ao estilo anterior.
            var plain = styled
            plain = MarkdownInputRule.clear(rule, from: plain, block: block)
            typingAttributes = plain
            onContentChanged?()
            return
        }
    }

    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard shouldChangeText(in: range, replacementString: text.string) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + text.length, length: 0))
    }

    // MARK: Estilos inline

    func toggleInline(_ style: InlineStyle) {
        let range = selectedRange()
        var attrs = range.length > 0
            ? (textStorage?.attributes(at: range.location, effectiveRange: nil) ?? [:])
            : typingAttributes
        let font = attrs[.font] as? NSFont ?? MarkdownTheme.body
        let traits = NSFontManager.shared.traits(of: font)
        let block = MarkdownBlock(rawValue: attrs[.mdBlock] as? String ?? "") ?? .paragraph

        switch style {
        case .bold, .italic:
            let mask: NSFontTraitMask = style == .bold ? .boldFontMask : .italicFontMask
            let has = traits.contains(mask)
            let newFont = has
                ? NSFontManager.shared.convert(font, toNotHaveTrait: mask)
                : NSFontManager.shared.convert(font, toHaveTrait: mask)
            attrs[.font] = newFont
        case .strike:
            let has = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            attrs[.strikethroughStyle] = has ? 0 : NSUnderlineStyle.single.rawValue
        case .code:
            let has = attrs[.mdCode] as? Bool ?? false
            if has {
                attrs.removeValue(forKey: .mdCode)
                attrs.removeValue(forKey: .backgroundColor)
                attrs[.font] = MarkdownTheme.font(for: block, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask))
            } else {
                attrs[.mdCode] = true
                attrs[.backgroundColor] = MarkdownTheme.codeBackground
                attrs[.font] = MarkdownTheme.font(for: block, code: true)
            }
        }

        if range.length > 0 {
            guard shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage?.beginEditing()
            textStorage?.enumerateAttributes(in: range) { runAttrs, runRange, _ in
                var updated = runAttrs
                for key: NSAttributedString.Key in [.font, .strikethroughStyle, .mdCode, .backgroundColor] {
                    if let value = attrs[key] { updated[key] = value } else { updated.removeValue(forKey: key) }
                }
                textStorage?.setAttributes(updated, range: runRange)
            }
            textStorage?.endEditing()
            didChangeText()
        }
        typingAttributes = attrs
        onContentChanged?()
    }

    // MARK: Blocos

    func setBlock(_ block: MarkdownBlock) {
        let range = paragraphsRange(for: selectedRange())
        applyParagraph(block, lists: [], to: range)
    }

    func toggleList(ordered: Bool) {
        let range = paragraphsRange(for: selectedRange())
        let attrs = attributes(atParagraph: range)
        let lists = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        let isSame = lists.last.map { ($0.markerFormat == .decimal) == ordered } ?? false
        if isSame {
            applyParagraph(.paragraph, lists: [], to: range)
        } else {
            let list = NSTextList(markerFormat: ordered ? .decimal : .disc, options: 0)
            applyParagraph(.paragraph, lists: [list], to: range)
        }
    }

    /// Reaplica bloco/lista em todos os parágrafos do intervalo, preservando ênfases.
    private func applyParagraph(_ block: MarkdownBlock, lists: [NSTextList], to range: NSRange) {
        guard let storage = textStorage else { return }
        if range.length == 0 {
            var attrs = MarkdownTheme.attributes(block: block, listDepth: lists.count, lists: lists)
            attrs.removeValue(forKey: .link)
            typingAttributes = attrs
            let paragraphAttrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: attrs[.paragraphStyle]!, .mdBlock: block.rawValue, .font: attrs[.font]!,
                .foregroundColor: attrs[.foregroundColor]!,
            ]
            if storage.length > 0, range.location < storage.length {
                // Parágrafo vazio no meio do texto: aplica ao caractere de quebra.
                storage.addAttributes(paragraphAttrs, range: NSRange(location: range.location, length: 1))
            }
            // O próximo texto digitado recebe o estilo (inclusive a lista).
            pendingParagraphAttributes = paragraphAttrs
            onContentChanged?()
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { runAttrs, runRange, _ in
            let font = runAttrs[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let code = runAttrs[.mdCode] as? Bool ?? false
            var attrs = MarkdownTheme.attributes(
                block: block,
                bold: traits.contains(.boldFontMask) && block.headingLevel == nil,
                italic: traits.contains(.italicFontMask),
                code: code && block != .codeBlock,
                strike: (runAttrs[.strikethroughStyle] as? Int ?? 0) != 0,
                link: runAttrs[.link] as? URL,
                listDepth: lists.count,
                lists: lists
            )
            if block == .codeBlock { attrs.removeValue(forKey: .mdCode) }
            storage.setAttributes(attrs, range: runRange)
        }
        storage.endEditing()
        didChangeText()
        var typing = MarkdownTheme.attributes(block: block, listDepth: lists.count, lists: lists)
        typing.removeValue(forKey: .link)
        typingAttributes = typing
    }

    // MARK: Link

    func promptLink() {
        let range = selectedRange()
        let existing = range.length > 0 ? textStorage?.attribute(.link, at: range.location, effectiveRange: nil) : nil
        let alert = NSAlert()
        alert.messageText = "Link"
        alert.informativeText = range.length > 0 ? "URL para o texto selecionado." : "URL (o endereço será inserido como texto)."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        if existing != nil { alert.addButton(withTitle: "Remover link") }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = (existing as? URL)?.absoluteString ?? (existing as? String) ?? "https://"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            textStorage?.removeAttribute(.link, range: range)
            textStorage?.removeAttribute(.underlineStyle, range: range)
            textStorage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            didChangeText()
            return
        }
        guard response == .alertFirstButtonReturn,
              let url = URL(string: field.stringValue.trimmingCharacters(in: .whitespaces)),
              Self.isAllowedLink(url) else { return }
        if range.length == 0 {
            let attrs = MarkdownTheme.attributes(block: .paragraph, link: url)
            insertText(NSAttributedString(string: url.absoluteString, attributes: attrs), replacementRange: range)
            typingAttributes = MarkdownTheme.typingAttributes
        } else {
            textStorage?.addAttributes([.link: url, .foregroundColor: NSColor.linkColor,
                                        .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
        }
        didChangeText()
    }

    // MARK: Utilitários

    private func paragraphRange(at location: Int) -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        return ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
    }

    private func paragraphsRange(for selection: NSRange) -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        return ns.paragraphRange(for: NSRange(location: min(selection.location, ns.length),
                                              length: min(selection.length, ns.length - min(selection.location, ns.length))))
    }

    private func attributes(atParagraph range: NSRange) -> [NSAttributedString.Key: Any] {
        guard let storage = textStorage, storage.length > 0 else { return typingAttributes }
        let location = min(range.location, storage.length - 1)
        return storage.attributes(at: location, effectiveRange: nil)
    }
}
