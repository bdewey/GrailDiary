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

public extension Note {
  /// When you edit markdown notes, the challenge templates extracted from the text don't have "identity."
  /// To preserve prompt history across note edits, we need to make sure that prompts get the same key. However,
  /// to prevent "history confusion," we also need to make sure we don't share keys across substantially different prompts.
  ///
  /// This method tries to make sure that challenges between two versions of a note use the same key if and only if
  /// those challenges are identical or nearly-identical.
  mutating func assignMatchingTemplateIdentifiers(
    from otherNote: Note
  ) {
    // This will hold the re-keyed prompts.
    var remappedTemplates = [ContentKey: PromptCollection]()

    // Consider all keys currently used as "temporary" -- they will get reassigned.
    var temporaryKeys = Set(promptCollections.keys)

    // Group all keys of otherNote by the "fingerprint" of the prompt (type & count of prompts)
    let otherTuples = otherNote.promptCollections.map { (key: $0.value.fingerprint, value: $0.key) }
    var otherKeys = Dictionary(grouping: otherTuples, by: { $0.key })

    // Phase 1: Look for exact matches.

    assignKeys(
      matching: { $0.rawValue == $1.rawValue },
      temporaryKeys: &temporaryKeys,
      challengeTemplates: promptCollections,
      otherKeys: &otherKeys,
      otherChallengeTemplates: otherNote.promptCollections,
      remappedTemplates: &remappedTemplates
    )

    // Phase 2: Look for "close enough" matches

    assignKeys(
      matching: { $0.closeEnough(to: $1) },
      temporaryKeys: &temporaryKeys,
      challengeTemplates: promptCollections,
      otherKeys: &otherKeys,
      otherChallengeTemplates: otherNote.promptCollections,
      remappedTemplates: &remappedTemplates
    )

    // Final phase: Anything left in temporaryKeys needs a new, unique key.
    // Note that keys generated by the migration process don't follow the PromptCollectionKey standard; in this case
    // though it's OK to start numbering keys about anywhere as there will be no collisions with old key values.
    let maxOtherIndex = otherNote.promptCollections.keys
      .map { PromptCollectionKey(rawValue: $0)?.numericIndex ?? otherNote.promptCollections.count }
      .reduce(0, max)

    for (index, temporaryKey) in temporaryKeys.enumerated() {
      remappedTemplates[PromptCollectionKey(numericIndex: maxOtherIndex + index + 1).rawValue] = promptCollections[temporaryKey]
    }

    // Done. Validate.
    assert(remappedTemplates.count == promptCollections.count)
    promptCollections = remappedTemplates
  }
}

private func assignKeys(
  matching predicate: (PromptCollection, PromptCollection) -> Bool,
  temporaryKeys: inout Set<Note.ContentKey>,
  challengeTemplates: [Note.ContentKey: PromptCollection],
  otherKeys: inout [TemplateFingerprint: [(key: TemplateFingerprint, value: Note.ContentKey)]],
  otherChallengeTemplates: [Note.ContentKey: PromptCollection],
  remappedTemplates: inout [Note.ContentKey: PromptCollection]
) {
  var successfullyRemappedKeys = Set<Note.ContentKey>()
  for temporaryKey in temporaryKeys {
    let promptCollection = challengeTemplates[temporaryKey]!
    if let (candidate, remainder) = otherKeys[promptCollection.fingerprint, default: []].findFirst(
      where: { (_, otherKey) -> Bool in
        let otherPromptCollection = otherChallengeTemplates[otherKey]!
        return predicate(promptCollection, otherPromptCollection)
      }
    ) {
      remappedTemplates[candidate.value] = promptCollection
      otherKeys[candidate.key] = remainder
      successfullyRemappedKeys.insert(temporaryKey)
    }
  }
  temporaryKeys.subtract(successfullyRemappedKeys)
}

private struct TemplateFingerprint: Hashable {
  let templateType: PromptType
  let challengeCount: Int
}

private extension PromptCollection {
  var fingerprint: TemplateFingerprint {
    TemplateFingerprint(templateType: type, challengeCount: prompts.count)
  }

  func closeEnough(to other: PromptCollection) -> Bool {
    assert(other.type == type)
    assert(other.prompts.count == prompts.count)
    let diff = rawValue.difference(from: other.rawValue)
    return diff.count < rawValue.count
  }
}

extension Array {
  func findFirst(where predicate: (Element) -> Bool) -> (value: Element, remainder: [Element])? {
    var value: Element?
    var remainder = [Element]()
    for element in self {
      if value == nil, predicate(element) {
        value = element
      } else {
        remainder.append(element)
      }
    }
    if let value = value {
      return (value: value, remainder: remainder)
    } else {
      return nil
    }
  }
}
