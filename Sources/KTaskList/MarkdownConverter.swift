import AppKit
import Foundation

/// Tipo de bloco de um parágrafo no editor (guardado como atributo do texto).
enum MarkdownBlock: String {
    case paragraph = "p"
    case heading1 = "h1", heading2 = "h2", heading3 = "h3"
    case quote
    case codeBlock = "code"

    var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }

    static func heading(_ level: Int) -> MarkdownBlock {
        switch max(1, min(level, 3)) {
        case 1: return .heading1
        case 2: return .heading2
        default: return .heading3
        }
    }
}

extension NSAttributedString.Key {
    /// Bloco Markdown do parágrafo (`MarkdownBlock.rawValue`).
    static let mdBlock = NSAttributedString.Key("br.com.khori.ktasklist.mdBlock")
    /// Marca trechos de código inline.
    static let mdCode = NSAttributedString.Key("br.com.khori.ktasklist.mdCode")
}

/// Fontes e estilos usados no editor WYSIWYG.
enum MarkdownTheme {
    static let bodySize: CGFloat = 13
    static let body = NSFont.systemFont(ofSize: bodySize)
    static let code = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
    static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
    static let listIndent: CGFloat = 22

    static func font(for block: MarkdownBlock, bold: Bool = false, italic: Bool = false, code: Bool = false) -> NSFont {
        var base: NSFont
        switch block {
        case .heading1: base = NSFont.systemFont(ofSize: 20, weight: .bold)
        case .heading2: base = NSFont.systemFont(ofSize: 17, weight: .bold)
        case .heading3: base = NSFont.systemFont(ofSize: 15, weight: .semibold)
        case .codeBlock: base = Self.code
        case .quote, .paragraph: base = code ? Self.code : Self.body
        }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            base = NSFontManager.shared.convert(base, toHaveTrait: traits)
        }
        return base
    }

    static func paragraphStyle(for block: MarkdownBlock, listDepth: Int, lists: [NSTextList]) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = block.headingLevel != nil ? 6 : 4
        style.paragraphSpacingBefore = block.headingLevel != nil ? 8 : 0
        style.lineSpacing = 1
        if !lists.isEmpty {
            style.textLists = lists
            style.headIndent = listIndent * CGFloat(listDepth)
            style.firstLineHeadIndent = listIndent * CGFloat(listDepth - 1)
        } else if block == .quote {
            style.headIndent = 14
            style.firstLineHeadIndent = 14
        } else if block == .codeBlock {
            style.paragraphSpacing = 0
        }
        return style
    }

    /// Atributos completos de um trecho.
    static func attributes(block: MarkdownBlock, bold: Bool = false, italic: Bool = false, code: Bool = false,
                           strike: Bool = false, link: URL? = nil, listDepth: Int = 0,
                           lists: [NSTextList] = []) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: block, bold: bold, italic: italic, code: code),
            .paragraphStyle: paragraphStyle(for: block, listDepth: listDepth, lists: lists),
            .mdBlock: block.rawValue,
            .foregroundColor: block == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        if code || block == .codeBlock {
            attrs[.backgroundColor] = codeBackground
            if code { attrs[.mdCode] = true }
        }
        if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link {
            attrs[.link] = link
            attrs[.foregroundColor] = NSColor.linkColor
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    static var typingAttributes: [NSAttributedString.Key: Any] { attributes(block: .paragraph) }
}

/// Conversão Markdown ⇄ NSAttributedString estilizado para o editor.
enum MarkdownConverter {

    // MARK: - Markdown → texto estilizado

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: MarkdownTheme.typingAttributes)
        }

        let result = NSMutableAttributedString()
        var lastBlockID: Int?
        var listObjects: [Int: NSTextList] = [:]

        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            var block = MarkdownBlock.paragraph
            var blockID: Int?
            var lists: [NSTextList] = []

            if let intent = run.presentationIntent {
                // Componentes vêm do mais interno para o mais externo.
                for component in intent.components {
                    switch component.kind {
                    case .paragraph:
                        if blockID == nil { blockID = component.identity }
                    case .header(let level):
                        block = .heading(level)
                        if blockID == nil { blockID = component.identity }
                    case .blockQuote:
                        if block == .paragraph { block = .quote }
                    case .codeBlock:
                        block = .codeBlock
                        if blockID == nil { blockID = component.identity }
                    case .listItem:
                        if blockID == nil { blockID = component.identity }
                    case .orderedList:
                        lists.append(list(for: component.identity, ordered: true, in: &listObjects))
                    case .unorderedList:
                        lists.append(list(for: component.identity, ordered: false, in: &listObjects))
                    case .thematicBreak:
                        text = "———"
                        if blockID == nil { blockID = component.identity }
                    default:
                        if blockID == nil { blockID = component.identity }
                    }
                }
            }
            // Listas vieram da mais interna para a externa; o estilo espera da externa para a interna.
            lists.reverse()

            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.softBreak) { text = " " }
            if inline.contains(.lineBreak) { text = "\n" }

            if block == .codeBlock, text.hasSuffix("\n") { text.removeLast() }

            if let lastBlockID, blockID != lastBlockID {
                result.append(NSAttributedString(string: "\n", attributes: result.lastParagraphAttributes))
            }
            lastBlockID = blockID ?? lastBlockID

            let attrs = MarkdownTheme.attributes(
                block: block,
                bold: inline.contains(.stronglyEmphasized),
                italic: inline.contains(.emphasized),
                code: inline.contains(.code),
                strike: inline.contains(.strikethrough),
                link: run.link,
                listDepth: lists.count,
                lists: lists
            )
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        if result.length == 0 {
            return NSAttributedString(string: "", attributes: MarkdownTheme.typingAttributes)
        }
        return result
    }

    private static func list(for identity: Int, ordered: Bool, in cache: inout [Int: NSTextList]) -> NSTextList {
        if let existing = cache[identity] { return existing }
        let list = NSTextList(markerFormat: ordered ? .decimal : .disc, options: 0)
        cache[identity] = list
        return list
    }

    // MARK: - Texto estilizado → Markdown

    private struct InlineRun: Equatable {
        var text: String
        var bold = false, italic = false, code = false, strike = false
        var link: URL?

        var styleKey: String { "\(bold)\(italic)\(code)\(strike)\(link?.absoluteString ?? "")" }
    }

    private struct Paragraph {
        var block: MarkdownBlock
        var listDepth: Int
        var ordered: Bool
        var listID: ObjectIdentifier?
        var runs: [InlineRun]
        var isEmpty: Bool { runs.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        let paragraphs = splitParagraphs(attributed)
        var lines: [String] = []
        var previous: Paragraph?
        var ordinal = 0
        var inCode = false

        for paragraph in paragraphs {
            if paragraph.block == .codeBlock {
                if !inCode {
                    if let last = lines.last, !last.isEmpty { lines.append("") }
                    lines.append("```"); inCode = true
                }
                lines.append(paragraph.runs.map(\.text).joined())
                previous = paragraph
                continue
            }
            if inCode { lines.append("```"); inCode = false }

            if paragraph.isEmpty && paragraph.listDepth == 0 && paragraph.block.headingLevel == nil {
                // Parágrafo vazio: só garante a separação.
                if let last = lines.last, !last.isEmpty { lines.append("") }
                previous = paragraph
                continue
            }

            let inline = serializeInline(paragraph.runs, allowEmphasis: paragraph.block.headingLevel == nil)
            var line: String
            if paragraph.listDepth > 0 {
                let previousInList = (previous?.listDepth ?? 0) > 0
                let sameList = previousInList && previous?.listID == paragraph.listID
                ordinal = sameList ? ordinal + 1 : 1
                let indent = String(repeating: "  ", count: paragraph.listDepth - 1)
                line = indent + (paragraph.ordered ? "\(ordinal). " : "- ") + inline
                // Lista nova (ou outra lista) começa depois de uma linha em branco.
                let continuesList = previousInList && (sameList || paragraph.listDepth > 1 || (previous?.listDepth ?? 0) > 1)
                if !continuesList, let last = lines.last, !last.isEmpty { lines.append("") }
            } else {
                if let last = lines.last, !last.isEmpty { lines.append("") }
                switch paragraph.block {
                case .heading1: line = "# " + inline
                case .heading2: line = "## " + inline
                case .heading3: line = "### " + inline
                case .quote: line = "> " + inline
                default: line = inline
                }
            }
            lines.append(line)
            previous = paragraph
        }
        if inCode { lines.append("```") }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitParagraphs(_ attributed: NSAttributedString) -> [Paragraph] {
        let string = attributed.string as NSString
        var result: [Paragraph] = []
        var location = 0
        while location <= string.length {
            let lineRange = location < string.length
                ? string.lineRange(for: NSRange(location: location, length: 0))
                : NSRange(location: location, length: 0)
            var content = lineRange
            if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }

            let attrsLocation = min(content.location, max(0, attributed.length - 1))
            let attrs = attributed.length > 0 ? attributed.attributes(at: attrsLocation, effectiveRange: nil) : [:]
            let block = MarkdownBlock(rawValue: attrs[.mdBlock] as? String ?? "") ?? .paragraph
            let style = attrs[.paragraphStyle] as? NSParagraphStyle
            let lists = style?.textLists ?? []

            var runs: [InlineRun] = []
            if content.length > 0 {
                attributed.enumerateAttributes(in: content) { runAttrs, range, _ in
                    let font = runAttrs[.font] as? NSFont
                    let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
                    let run = InlineRun(
                        text: string.substring(with: range),
                        bold: traits.contains(.boldFontMask) && block.headingLevel == nil,
                        italic: traits.contains(.italicFontMask),
                        code: runAttrs[.mdCode] as? Bool ?? false,
                        strike: (runAttrs[.strikethroughStyle] as? Int ?? 0) != 0,
                        link: runAttrs[.link] as? URL ?? (runAttrs[.link] as? String).flatMap(URL.init(string:))
                    )
                    runs.append(run)
                }
            }
            result.append(Paragraph(block: block, listDepth: lists.count,
                                    ordered: lists.last?.markerFormat == .decimal,
                                    listID: lists.last.map(ObjectIdentifier.init), runs: runs))

            if lineRange.length == 0 { break }
            location = NSMaxRange(lineRange)
            if location == string.length, string.character(at: location - 1) != 0x0A { break }
        }
        return result
    }

    private static func serializeInline(_ runs: [InlineRun], allowEmphasis: Bool) -> String {
        // Funde trechos vizinhos com o mesmo estilo.
        var merged: [InlineRun] = []
        for run in runs {
            if var last = merged.last, last.styleKey == run.styleKey {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        var out = ""
        for run in merged {
            if run.code {
                out += "`" + run.text.replacingOccurrences(of: "`", with: "'") + "`"
                continue
            }
            let core = run.text.trimmingCharacters(in: .whitespaces)
            let leading = String(run.text.prefix { $0 == " " })
            let trailing = String(run.text.reversed().prefix { $0 == " " })
            if core.isEmpty { out += run.text; continue }

            var piece = escape(core)
            if allowEmphasis {
                if run.bold { piece = "**" + piece + "**" }
                if run.italic { piece = "*" + piece + "*" }
                if run.strike { piece = "~~" + piece + "~~" }
            }
            if let link = run.link { piece = "[" + piece + "](" + link.absoluteString + ")" }
            out += leading + piece + trailing
        }
        return out
    }

    /// Escapa caracteres que o parser interpretaria como marcação.
    private static func escape(_ text: String) -> String {
        var s = text
        for token in ["\\", "*", "_", "`", "~", "[", "]"] {
            s = s.replacingOccurrences(of: token, with: "\\" + token)
        }
        if let first = s.first, "#>-+".contains(first) { s = "\\" + s }
        if let match = s.range(of: #"^\d+\."#, options: .regularExpression) {
            s.insert("\\", at: s.index(before: match.upperBound))
        }
        return s
    }

    // MARK: - Heurísticas

    /// Texto colado parece Markdown (títulos, listas, ênfase, código, links)?
    static func looksLikeMarkdown(_ text: String) -> Bool {
        let patterns = [
            #"(?m)^#{1,6}\s"#, #"(?m)^\s*[-*+]\s"#, #"(?m)^\s*\d+\.\s"#, #"(?m)^>\s"#,
            #"\*\*[^*]+\*\*"#, #"(?<!\*)\*[^*\s][^*]*\*(?!\*)"#, #"`[^`]+`"#, #"```"#,
            #"\[[^\]]+\]\([^)]+\)"#, #"~~[^~]+~~"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Texto simples (sem marcação) para prévias em uma linha.
    static func plainText(fromMarkdown markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let text = (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) } ?? markdown
        return text
            .replacingOccurrences(of: #"(?m)^\s*(#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s+|```.*)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

private extension NSMutableAttributedString {
    /// Atributos do fim do texto (para a quebra de parágrafo herdar o estilo).
    var lastParagraphAttributes: [NSAttributedString.Key: Any] {
        guard length > 0 else { return MarkdownTheme.typingAttributes }
        var attrs = attributes(at: length - 1, effectiveRange: nil)
        attrs.removeValue(forKey: .link)
        attrs.removeValue(forKey: .underlineStyle)
        return attrs
    }
}
