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

import Foundation
import UIKit

public extension PromptType {
  static let quote = PromptType(rawValue: "prompt=quote", class: QuotePrompt.self)
}

public struct QuotePrompt: PromptCollection {
  public init(rawValue: String) {
    self.markdown = rawValue
  }

  public var templateIdentifier: ChallengeTemplateIdentifier?

  public var type: PromptType { return .quote }

  /// The quote template is itself a card.
  public var challenges: [Prompt] { return [self] }

  private let markdown: String
  public var rawValue: String {
    return markdown
  }

  public static func extract(from parsedString: ParsedString) -> [QuotePrompt] {
    guard let root = try? parsedString.result.get() else { return [] }
    let anchoredRoot = AnchoredNode(node: root, startIndex: 0)
    return anchoredRoot
      .findNodes(where: { $0.type == .blockquote })
      .compactMap { node -> QuotePrompt? in
        let chars = parsedString[node.range]
        return QuotePrompt(rawValue: String(utf16CodeUnits: chars, count: chars.count))
      }
  }
}

extension QuotePrompt: Prompt {
  public func promptView(
    database: NoteDatabase,
    properties: CardDocumentProperties
  ) -> PromptView {
    let view = TwoSidedCardView(frame: .zero)
    view.context = NSAttributedString(
      string: "Identify the source".uppercased(),
      attributes: [
        .font: UIFont.preferredFont(forTextStyle: .subheadline),
        .foregroundColor: UIColor.secondaryLabel,
        .kern: 2.0,
      ]
    )
    let (front, chapterAndVerse) = renderCardFront()
    view.front = front.trimmingTrailingWhitespace()
    let attribution = ParsedAttributedString(string: "—" + properties.attributionMarkdown + " " + chapterAndVerse, settings: .plainText(textStyle: .caption1))
    let back = NSMutableAttributedString()
    back.append(front.trimmingTrailingWhitespace())
    back.append(NSAttributedString(string: "\n\n"))
    back.append(attribution.trimmingTrailingWhitespace())
    view.back = back
    return view
  }

  public func renderCardFront(
  ) -> (front: NSAttributedString, chapterAndVerse: Substring) {
    let renderedMarkdown = ParsedAttributedString(string: markdown, settings: .plainText(textStyle: .body))
    let chapterAndVerse = renderedMarkdown.chapterAndVerseAnnotation ?? ""
    let front = renderedMarkdown.removingChapterAndVerseAnnotation()
    return (front: front, chapterAndVerse: chapterAndVerse)
  }
}

extension QuotePrompt: Equatable {
  public static func == (lhs: QuotePrompt, rhs: QuotePrompt) -> Bool {
    return lhs.markdown == rhs.markdown
  }
}
