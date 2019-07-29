// Copyright © 2017-present Brian's Brain. All rights reserved.

import MiniMarkdown
import UIKit

public protocol ConfiguresRenderers {
  func configureRenderers(_ renderers: inout [NodeType: RenderedMarkdown.RenderFunction])
}

extension UIDocument {
  /// Any UIDocument now has `openOrCreate` functionality.
  /// If opening the document doesn't succeed, try saving it with mode `.forCreating`.
  /// - parameter completionHandler: Optional handler to be called with a Bool indicating success.
  public func openOrCreate(completionHandler: ((Bool) -> Void)?) {
    open { success in
      // "the completion handler is called on the main queue" for open
      if success {
        completionHandler?(success)
      } else {
        self.save(to: self.fileURL, for: .forCreating, completionHandler: { success in
          // "the completion handler is called on the calling queue" for save
          DispatchQueue.main.async {
            try? self.load(fromContents: Data(), ofType: nil)
            completionHandler?(success)
          }
        })
      }
    }
  }
}
