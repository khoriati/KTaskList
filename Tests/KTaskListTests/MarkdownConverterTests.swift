import XCTest
@testable import KTaskList

final class MarkdownConverterTests: XCTestCase {
    private func roundTrip(_ md: String) -> String {
        MarkdownConverter.markdown(from: MarkdownConverter.attributedString(fromMarkdown: md))
    }

    func testHeadingsParagraphsAndEmphasisRoundTrip() {
        let md = """
        # Título

        Texto com **negrito**, *itálico*, `código` e ~~tachado~~.

        ## Sub

        Outro parágrafo.
        """
        XCTAssertEqual(roundTrip(md), md)
    }

    func testListsQuoteCodeBlockAndLinkRoundTrip() {
        let md = """
        Intro

        - um
        - dois

        1. primeiro
        2. segundo

        > citação

        ```
        let x = 1
        print(x)
        ```

        Veja [o site](https://example.com) agora.
        """
        XCTAssertEqual(roundTrip(md), md)
    }

    func testRenderedTextHasStylesAndOneParagraphPerLine() {
        let attributed = MarkdownConverter.attributedString(fromMarkdown: "# T\n\nCorpo **forte**\n\n- item")
        XCTAssertEqual(attributed.string, "T\nCorpo forte\nitem")
        let headingFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(headingFont?.pointSize, 20)
        XCTAssertEqual(attributed.attribute(.mdBlock, at: 0, effectiveRange: nil) as? String, "h1")
        let boldRange = (attributed.string as NSString).range(of: "forte")
        let boldFont = attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont!).contains(.boldFontMask))
        let itemRange = (attributed.string as NSString).range(of: "item")
        let style = attributed.attribute(.paragraphStyle, at: itemRange.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textLists.count, 1)
    }

    func testPlainTextEscapesMarkupCharacters() {
        let md = roundTrip("Preço 2*3 e a_b")
        XCTAssertEqual(md, "Preço 2\\*3 e a\\_b")
        XCTAssertEqual(MarkdownConverter.attributedString(fromMarkdown: md).string, "Preço 2*3 e a_b")
    }

    func testLooksLikeMarkdownAndPlainPreview() {
        XCTAssertTrue(MarkdownConverter.looksLikeMarkdown("# Olá\n- a"))
        XCTAssertTrue(MarkdownConverter.looksLikeMarkdown("texto **forte**"))
        XCTAssertFalse(MarkdownConverter.looksLikeMarkdown("apenas texto simples"))
        XCTAssertEqual(MarkdownConverter.plainText(fromMarkdown: "# Olá\n\n**mundo** `x`"), "Olá mundo x")
    }
}
