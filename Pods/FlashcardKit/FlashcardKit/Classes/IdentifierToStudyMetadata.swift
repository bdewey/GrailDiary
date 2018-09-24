// Copyright © 2018 Brian's Brain. All rights reserved.

import CommonplaceBook
import Foundation

extension Dictionary where Key == String, Value == StudyMetadata {

  public static let empty: [String: StudyMetadata] = [:]

  /// Builds a study session from vocabulary associations.
  func studySession(
    from cards: [Card],
    limit: Int,
    date: Date = Date()
  ) -> StudySession {
    let studyCards = cards
      .filter { self.eligibleForStudy(identifier: $0.identifier, on: date) }
      .shuffled()
      .prefix(limit)
    return StudySession(studyCards)
  }

  private func eligibleForStudy(identifier: String, on date: Date) -> Bool {
    let day = DayComponents(date)
    // If we have no record of this identifier, we can study it.
    return self[identifier]?.eligibleForStudy(on: day) ?? true
  }
}
