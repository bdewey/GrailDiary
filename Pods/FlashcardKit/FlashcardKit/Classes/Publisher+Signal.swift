// Copyright © 2018-present Brian's Brain. All rights reserved.

import CwlSignal
import Foundation
import TextBundleKit

/// Make the two "Result" enums equivalent. They are, but the compiler doesn't know that.
extension CwlSignal.Result {
  init(_ textResult: TextBundleKit.Result<Value>) {
    switch textResult {
    case .success(let value):
      self = .success(value)
    case .failure(let error):
      self = .failure(error)
    }
  }
}

private var subscriptionKey = "textBundleSubscription"

extension Signal {
  /// If we are bridging a Publisher to a Signal, we need a way to keep the Publisher subscription
  /// alive. That way is setting an associated property.
  fileprivate var textBundleSubscription: AnySubscription? {
    get {
      return objc_getAssociatedObject(self, &subscriptionKey) as? AnySubscription
    }
    set {
      objc_setAssociatedObject(self, &subscriptionKey, newValue, .OBJC_ASSOCIATION_RETAIN)
    }
  }
}

extension DocumentProperty {
  public var signal: Signal<Tagged<Value>> {
    let channel = Signal<Tagged<Value>>.channel().continuous()
    let subscription = subscribe { result in
      channel.input.send(result: CwlSignal.Result(result))
    }
    channel.signal.textBundleSubscription = subscription
    return channel.signal
  }
}
