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

/// A sequence of challenges for the learner to respond to.
public struct StudySession {
  public struct SessionChallengeIdentifier {
    public let noteIdentifier: Note.Identifier
    public let noteTitle: String
    public let challengeIdentifier: PromptIdentifier
  }

  /// The current set of cards to study.
  private var sessionChallengeIdentifiers: [SessionChallengeIdentifier]

  /// The current position in `cards`
  private var currentIndex: Int

  /// Identifiers of the cards that were answered correctly the first time.
  private(set) var answeredCorrectly: Set<PromptIdentifier> = []

  /// Identifiers of cards that were answered incorrectly at least once.
  private(set) var answeredIncorrectly: Set<PromptIdentifier> = []

  /// When the person started this particular study session.
  public var studySessionStartDate: Date?

  /// When the person ended this particular study session.
  public var studySessionEndDate: Date?

  public private(set) var results = [PromptIdentifier: AnswerStatistics]()

  /// Identifiers of cards that weren't answered at all in the study session.
  var didNotAnswerAtAll: Set<PromptIdentifier> {
    var didNotAnswer = allIdentifiers
    didNotAnswer.subtract(answeredCorrectly)
    didNotAnswer.subtract(answeredIncorrectly)
    return didNotAnswer
  }

  var allIdentifiers: Set<PromptIdentifier> {
    return sessionChallengeIdentifiers.allIdentifiers
  }

  /// Creates a study session where all cards come from a single document.
  public init<ChallengeIdentifiers: Sequence>(
    _ challengeIdentifiers: ChallengeIdentifiers,
    properties: CardDocumentProperties
  ) where ChallengeIdentifiers.Element == PromptIdentifier {
    let sessionChallengeIdentifiers = challengeIdentifiers.shuffled().map {
      SessionChallengeIdentifier(noteIdentifier: properties.documentName, noteTitle: properties.attributionMarkdown, challengeIdentifier: $0)
    }
    self.sessionChallengeIdentifiers = sessionChallengeIdentifiers
    self.currentIndex = self.sessionChallengeIdentifiers.startIndex
  }

  /// Creates an empty study session.
  public init() {
    self.sessionChallengeIdentifiers = []
    self.currentIndex = 0
  }

  /// The current card to study. Nil if we're done.
  public var currentCard: SessionChallengeIdentifier? {
    guard currentIndex < sessionChallengeIdentifiers.endIndex else { return nil }
    return sessionChallengeIdentifiers[currentIndex]
  }

  /// Record a correct or incorrect answer for the current card, and advance `currentCard`
  public mutating func recordAnswer(correct: Bool) {
    guard let currentCard = currentCard else { return }
    let identifier = currentCard.challengeIdentifier
    var statistics = results[currentCard.challengeIdentifier, default: AnswerStatistics.empty]
    if correct {
      if !answeredIncorrectly.contains(identifier) { answeredCorrectly.insert(identifier) }
      statistics.correct += 1
    } else {
      answeredIncorrectly.insert(identifier)
      sessionChallengeIdentifiers.append(currentCard)
      statistics.incorrect += 1
    }
    results[currentCard.challengeIdentifier] = statistics
    currentIndex += 1
  }

  public mutating func limit(to cardCount: Int) {
    sessionChallengeIdentifiers = Array(sessionChallengeIdentifiers.prefix(cardCount))
  }

  public func limiting(to cardCount: Int) -> StudySession {
    var copy = self
    copy.limit(to: cardCount)
    return copy
  }

  /// Make sure that we don't use multiple prompts from the same prompt template.
  public mutating func ensureUniqueChallengeTemplates() {
    var seenChallengeTemplateIdentifiers = Set<PromptIdentifier>()
    sessionChallengeIdentifiers = sessionChallengeIdentifiers
      .filter { sessionChallengeIdentifier -> Bool in
        var templateIdentifier = sessionChallengeIdentifier.challengeIdentifier
        templateIdentifier.promptIndex = 0
        if seenChallengeTemplateIdentifiers.contains(templateIdentifier) {
          return false
        } else {
          seenChallengeTemplateIdentifiers.insert(templateIdentifier)
          return true
        }
      }
  }

  public func ensuringUniqueChallengeTemplates() -> StudySession {
    var copy = self
    copy.ensureUniqueChallengeTemplates()
    return copy
  }

  public mutating func shuffle() {
    sessionChallengeIdentifiers.shuffle()
  }

  public func shuffling() -> StudySession {
    var copy = self
    copy.shuffle()
    return copy
  }

  /// Number of cards remaining in the study session.
  public var remainingCards: Int {
    return sessionChallengeIdentifiers.endIndex - currentIndex
  }

  public static func += (lhs: inout StudySession, rhs: StudySession) {
    lhs.sessionChallengeIdentifiers.append(contentsOf: rhs.sessionChallengeIdentifiers)
    lhs.sessionChallengeIdentifiers.shuffle()
    lhs.currentIndex = 0
  }
}

extension StudySession: Collection {
  public var startIndex: Int { return sessionChallengeIdentifiers.startIndex }
  public var endIndex: Int { return sessionChallengeIdentifiers.endIndex }
  public func index(after i: Int) -> Int {
    return sessionChallengeIdentifiers.index(after: i)
  }

  public subscript(position: Int) -> SessionChallengeIdentifier {
    return sessionChallengeIdentifiers[position]
  }
}

extension StudySession {
  public struct Statistics: Codable {
    public let startDate: Date
    public let duration: TimeInterval
    public let answeredCorrectly: Int
    public let answeredIncorrectly: Int
  }

  var statistics: Statistics? {
    guard let startDate = studySessionStartDate,
          let endDate = studySessionEndDate
    else { return nil }
    return Statistics(
      startDate: startDate,
      duration: endDate.timeIntervalSince(startDate),
      answeredCorrectly: answeredCorrectly.count,
      answeredIncorrectly: answeredIncorrectly.count
    )
  }
}

extension Sequence where Element == StudySession.SessionChallengeIdentifier {
  /// For a sequence of cards, return the set of all identifiers.
  var allIdentifiers: Set<PromptIdentifier> {
    return reduce(into: Set<PromptIdentifier>()) { $0.insert($1.challengeIdentifier) }
  }
}
