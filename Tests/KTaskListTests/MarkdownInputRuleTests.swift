import AppKit
import XCTest
@testable import KTaskList

@MainActor
final class MarkdownInputRuleTests: XCTestCase {
    private func makeEditor() -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.typingAttributes = MarkdownTheme.typingAttributes
        return view
    }

    private func type(_ text: String, into view: MarkdownTextView) {
        for ch in text {
            if ch == "\n" { view.insertNewline(nil) } else { view.insertText(String(ch), replacementRange: view.selectedRange()) }
        }
    }

    private func markdown(_ view: MarkdownTextView) -> String {
        MarkdownConverter.markdown(from: view.textStorage!)
    }

    func testHashSpaceBecomesHeading() {
        let view = makeEditor()
        type("## Título\nCorpo", into: view)
        XCTAssertEqual(markdown(view), "## Título\n\nCorpo")
        XCTAssertEqual(view.textStorage?.attribute(.mdBlock, at: 0, effectiveRange: nil) as? String, "h2")
    }

    func testDashAndNumberBecomeLists() {
        let view = makeEditor()
        // Enter continua a lista; Enter em item vazio encerra.
        type("- um\ndois\n\n1. a\nb\n\nfim", into: view)
        XCTAssertEqual(markdown(view), "- um\n- dois\n\n1. a\n2. b\n\nfim")
    }

    func testQuoteAndCodeFence() {
        let view = makeEditor()
        type("> nota\n```\nlet x = 1\n\ndepois", into: view)
        XCTAssertEqual(markdown(view), "> nota\n\n```\nlet x = 1\n```\n\ndepois")
    }

    func testInlineMarkersApplyStyles() {
        let view = makeEditor()
        type("a **forte** e *leve* com `cod` e ~~x~~ fim", into: view)
        XCTAssertEqual(view.string, "a forte e leve com cod e x fim")
        XCTAssertEqual(markdown(view), "a **forte** e *leve* com `cod` e ~~x~~ fim")
    }
}
