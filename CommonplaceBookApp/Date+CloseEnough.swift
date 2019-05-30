// Copyright © 2017-present Brian's Brain. All rights reserved.

import Foundation

public extension Date {
  /// True if the receiver and `other` are "close enough"
  func withinInterval(_ timeInterval: TimeInterval, of other: Date) -> Bool {
    return abs(timeIntervalSince(other)) < timeInterval
  }
}
