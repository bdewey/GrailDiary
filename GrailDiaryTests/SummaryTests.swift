//
//  SummaryTests.swift
//  CommonplaceBookAppTests
//
//  Created by Brian Dewey on 6/20/21.
//  Copyright © 2021 Brian's Brain. All rights reserved.
//

import GrailDiary
import TextMarkupKit
import XCTest

final class SummaryTests: XCTestCase {
  func testSummary() {
    let example = """
    # _Book_, Author (Year)

    tl;dr: I loved it. **Everyone** should read it.

    Detailed notes here.
    """

    parseText(
      example,
      expectedStructure: "(document (header delimiter tab (emphasis delimiter text delimiter) text) blank_line (summary summary_delimiter (summary_body text (strong_emphasis delimiter text delimiter) text)) blank_line (paragraph text))"
    )
  }

  func testCaseInsensitiveSummary() {
    let example = """
    # _Book_, Author (Year)

    Tl;dr: I loved it. **Everyone** should read it.

    Detailed notes here.
    """

    parseText(
      example,
      expectedStructure: "(document (header delimiter tab (emphasis delimiter text delimiter) text) blank_line (summary summary_delimiter (summary_body text (strong_emphasis delimiter text delimiter) text)) blank_line (paragraph text))"
    )
  }

  private func parseText(_ text: String, expectedStructure: String) {
    let parsedString = ParsedString(text, grammar: GrailDiaryGrammar.shared)
    XCTAssertNoThrow(try parsedString.parsedResultsThatMatch(expectedStructure))
  }
}
