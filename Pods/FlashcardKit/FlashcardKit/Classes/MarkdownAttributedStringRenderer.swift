// Copyright © 2018 Brian's Brain. All rights reserved.

import Foundation
import MiniMarkdown

// TODO: Can I make a single generic structure with this and MarkdownStringRenderer?

struct MarkdownAttributedStringRenderer {
  public typealias RenderFunction = (Node) -> NSAttributedString
  public var renderFunctions: [NodeType: RenderFunction] = [:]

  public func render(node: Node) -> NSAttributedString {
    return renderFunctions[node.type]?(node) ?? node.children.map { render(node: $0) }.joined()
  }
}

extension Array where Element == NSAttributedString {
  func joined() -> NSAttributedString {
    let attributedString = NSMutableAttributedString()
    for element in self {
      attributedString.append(element)
    }
    return attributedString
  }
}