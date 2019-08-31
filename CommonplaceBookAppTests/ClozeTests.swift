// Copyright © 2017-present Brian's Brain. All rights reserved.

@testable import CommonplaceBookApp
@testable import MiniMarkdown
import XCTest
import Yams

final class ClozeTests: XCTestCase {
  private let parsingRules: ParsingRules = {
    var parsingRules = ParsingRules()
    parsingRules.inlineParsers.parsers.insert(Cloze.nodeParser, at: 0)
    return parsingRules
  }()

  func testFindClozeInText() {
    let example = """
    # Mastering the verb "to be"

    In Spanish, there are two verbs "to be": *ser* and *estar*.

    1. *Ser* is used to identify a person, an animal, a concept, a thing, or any noun.
    2. *Estar* is used to show location.
    3. *Ser*, with an adjective, describes the "norm" of a thing.
       - La nieve ?[to be](es) blanca.
    4. *Estar* with an adjective shows a "change" or "condition."
    """
    let blocks = parsingRules.parse(example)
    XCTAssertEqual(blocks[4].type, .list)
    let clozeNodes = blocks.map { $0.findNodes(where: { $0.type == .cloze }) }.joined()
    XCTAssertEqual(clozeNodes.count, 1)
    if let cloze = clozeNodes.first as? Cloze {
      XCTAssertEqual(cloze.slice.substring, "?[to be](es)")
      XCTAssertEqual(cloze.hiddenText, "es")
      XCTAssertEqual(cloze.hint, "to be")
    }
  }

  func testMultipleClozesInAnItem() {
    let example = """
    * Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?
    """
    let blocks = parsingRules.parse(example)
    XCTAssertEqual(blocks.count, 1)
    let clozeCards = ClozeTemplate.extract(from: blocks).cards as! [ClozeCard] // swiftlint:disable:this force_cast
    XCTAssertEqual(clozeCards.count, 2)
    XCTAssertEqual(
      clozeCards[1].markdown,
      "Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?"
    )
    XCTAssertEqual(clozeCards[1].clozeIndex, 1)
    let cardFrontRenderer = MarkdownAttributedStringRenderer.cardFront(
      hideClozeAt: clozeCards[0].clozeIndex
    )
    let node = parsingRules.parse(clozeCards[0].markdown)[0]
    XCTAssertEqual(
      cardFrontRenderer.render(node: node).string,
      "Yo to be de España. ¿De dónde es ustedes?"
    )
    XCTAssertEqual(
      clozeCards[1].cardFrontRenderer().render(node: node).string,
      "Yo soy de España. ¿De dónde to be ustedes?"
    )
  }

  func testYamlEncodingIsJustMarkdown() {
    let example = """
    * Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?
    """
    let blocks = parsingRules.parse(example)
    XCTAssertEqual(blocks.count, 1)
    guard let template = ClozeTemplate.extract(from: blocks).first else {
      XCTFail("Could not load template")
      return
    }

    do {
      let text = try YAMLEncoder().encode(template)
      print(text)
      let decoder = YAMLDecoder()
      let decoded = try decoder.decode(ClozeTemplate.self, from: text, userInfo: [.markdownParsingRules: parsingRules])
      XCTAssertEqual(decoded.challenges.count, template.challenges.count)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testClozeFormatting() {
    // Simple storage that will mark clozes as bold.
    let textStorage = MiniMarkdownTextStorage(
      parsingRules: parsingRules,
      formatters: [.cloze: { $1.bold = true }],
      renderers: [:]
    )
    let layoutManager = NSLayoutManager()
    textStorage.addLayoutManager(layoutManager)
    let textContainer = NSTextContainer()
    layoutManager.addTextContainer(textContainer)
    let textView = MarkdownEditingTextView(frame: .zero, textContainer: textContainer)
    textView.textContainerInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    textView.insertText("Testing")
    textView.selectedRange = NSRange(location: 0, length: 7)

    let range = textView.selectedRange
    textView.selectedRange = NSRange(location: range.upperBound, length: 0)
    textView.insertText(")")
    textView.selectedRange = NSRange(location: range.lowerBound, length: 0)
    textView.insertText("?[](")
    textView.selectedRange = NSRange(location: range.upperBound + 4, length: 0)

    var testRange = NSRange(location: NSNotFound, length: 0)
    // swiftlint:disable:next force_cast
    let actualFont = textStorage.attributes(at: 0, effectiveRange: &testRange)[.font] as! UIFont
    XCTAssert(actualFont.fontDescriptor.symbolicTraits.contains(.traitBold))
    XCTAssertEqual(testRange, NSRange(location: 0, length: 12))
  }
}
