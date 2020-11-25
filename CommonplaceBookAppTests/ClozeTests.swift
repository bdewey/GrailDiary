//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

@testable import CommonplaceBookApp
import XCTest

final class ClozeTests: XCTestCase {
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
    let buffer = ParsedString(example, grammar: MiniMarkdownGrammar())
    let templates = ClozeTemplate.extract(from: buffer)
    XCTAssertEqual(templates.count, 1)
  }

  func testMultipleClozesInAnItem() {
    let example = """
    * Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?
    """
    let buffer = ParsedString(example, grammar: MiniMarkdownGrammar.shared)
    let clozeCards = ClozeTemplate.extract(from: buffer).cards as! [ClozeCard] // swiftlint:disable:this force_cast
    XCTAssertEqual(clozeCards.count, 2)
    XCTAssertEqual(
      clozeCards[1].markdown,
      "Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?"
    )
    XCTAssertEqual(clozeCards[1].clozeIndex, 1)
    let renderedFront = ParsedAttributedString(string: clozeCards[0].markdown, settings: .clozeRenderer(hidingClozeAt: clozeCards[0].clozeIndex))
    XCTAssertEqual(
      renderedFront.string,
      "Yo to be de España. ¿De dónde es ustedes?"
    )
    XCTAssertEqual(
      ParsedAttributedString(
        string: clozeCards[1].markdown,
        settings: .clozeRenderer(hidingClozeAt: clozeCards[1].clozeIndex)
      ).string,
      "Yo soy de España. ¿De dónde to be ustedes?"
    )
    let renderedBack = ParsedAttributedString(string: clozeCards[0].markdown, settings: .clozeRenderer(highlightingClozeAt: clozeCards[0].clozeIndex))
    XCTAssertEqual(
      renderedBack.string,
      "Yo soy de España. ¿De dónde es ustedes?"
    )
  }

  func testYamlEncodingIsJustMarkdown() {
    let example = """
    * Yo ?[to be](soy) de España. ¿De dónde ?[to be](es) ustedes?
    """
    let decoded = ClozeTemplate(rawValue: example)
    XCTAssertEqual(decoded?.challenges.count, 2)
  }

  func testClozeFormatting() {
    // Simple storage that will mark clozes as bold.
    let textStorage = ParsedTextStorage(storage: ParsedAttributedString(
      string: "",
      grammar: MiniMarkdownGrammar(),
      defaultAttributes: [:],
      formattingFunctions: [.cloze: { $1.bold = true }],
      replacementFunctions: [:]
    ))
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
    XCTAssertEqual(testRange, NSRange(location: 0, length: 4))
  }
}
