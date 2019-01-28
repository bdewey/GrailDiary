// Copyright © 2017-present Brian's Brain. All rights reserved.

import XCTest

private enum Identifiers {
  static let backButton = "Back"
  static let currentCardView = "current-card"
  static let documentList = "document-list"
  static let editDocumentView = "edit-document-view"
  static let newDocumentButton = "new-document"
  static let studyButton = "study-button"
}

private enum TestContent {
  static let singleCloze = """
  Cloze test
  #testing
  - This is a file with a ?[](cloze).
  """

  static func pickleText(title: String) -> String {
    let text = """
    \(title)
    #testing
    - Peter Piper picked a ?[unit of pickles](peck) of pickled peppers.
    """
    return text
  }

  static let doubleCloze = """
  Two cloze document
  #testing
  - Cards with a fill-in-the-blank -- is called a "?[](cloze)".
  The 45th President of the United States is ?[cheeto](Donald Trump).

  The question about Trump should be in an auto-continue list.
  """

  static let quote = """
  *Educated*, Tara Westover

  ## Quotes

  > It’s a tranquillity born of sheer immensity; it calms with its very magnitude, which renders the merely human of no consequence.
  > Ain’t nothin’ ?[](funnier) than real life, I tell you what. (34)
  """
}

final class CommonplaceBookAppUITests: XCTestCase {
  var application: XCUIApplication!

  override func setUp() {
    // In UI tests it is usually best to stop immediately when a failure occurs.
    continueAfterFailure = false

    application = XCUIApplication()
    application.launchArguments.append("--uitesting")
    application.launch()

    XCUIDevice.shared.orientation = .portrait
  }

  func testHasNewDocumentButton() {
    let newDocumentButton = application.buttons[Identifiers.newDocumentButton]
    XCTAssertTrue(newDocumentButton.exists)
  }

  func testNewDocumentButtonWorks() {
    let newDocumentButton = application.buttons[Identifiers.newDocumentButton]
    newDocumentButton.tap()
    waitUntilElementExists(application.textViews[Identifiers.editDocumentView])
  }

  func testNewDocumentCanBeEdited() {
    createDocument(with: "Test Document")
    waitUntilElementExists(application.staticTexts["Test Document"])
  }

  func testStudyButtonEnabledAfterCreatingClozeContent() {
    createDocument(with: TestContent.singleCloze)
    waitUntilElementEnabled(application.buttons[Identifiers.studyButton])
  }

  func testStudyButtonStartsDisabled() {
    let studyButton = application.buttons[Identifiers.studyButton]
    waitUntilElementExists(studyButton)
    XCTAssertFalse(studyButton.isEnabled)
  }

  func testTableHasSingleRowAfterClozeContent() {
    createDocument(with: TestContent.singleCloze)
    waitUntilElementEnabled(application.buttons[Identifiers.studyButton])
    let documentList = application.collectionViews[Identifiers.documentList]
    waitUntilElementExists(documentList)
    XCTAssertEqual(documentList.cells.count, 1)
  }

  func testCreateMultipleFiles() {
    let numberOfFiles = 5
    for i in 1 ... numberOfFiles {
      createDocument(with: TestContent.pickleText(title: "Document \(i)"))
    }
    let finalTitle = "Document \(numberOfFiles)"
    let finalTitleLabel = application.staticTexts[finalTitle]
    waitUntilElementExists(finalTitleLabel)
    wait(
      for: NSPredicate(format: "cells.count == \(numberOfFiles)"),
      evaluatedWith: application.collectionViews[Identifiers.documentList],
      message: "Expected \(numberOfFiles) rows"
    )
  }

  func testStudyFromASingleDocument() {
    createDocument(with: TestContent.doubleCloze)
    study(expectedCards: 2)
  }

  func testStudyQuotes() {
    createDocument(with: TestContent.quote)
    study(expectedCards: 3)
  }

  func testRotation() {
    createDocument(with: TestContent.doubleCloze)
    let collectionView = application.collectionViews[Identifiers.documentList]
    let cell = collectionView.cells["Two cloze document"]
    waitUntilElementExists(cell)
    let expectedWidthAfterRotation = collectionView.frame.height
    XCTAssertEqual(collectionView.frame.width, cell.frame.width)
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(collectionView.exists)
    waitUntilElementExists(cell)
    XCTAssertEqual(collectionView.frame.width, cell.frame.width)
    XCTAssertEqual(expectedWidthAfterRotation, cell.frame.width)
  }

  func testLimitStudySessionToTwenty() {
    var lines = [String]()
    lines.append("The Shining\n* ")
    for i in 0 ..< 25 {
      lines.append("All work and no play makes ?[who?](Jack) a dull boy. \(i)\n")
    }
    createDocument(with: lines)
    waitUntilElementExists(application.staticTexts["25 cards."])
    study(expectedCards: 20, noCardsLeft: false)
    waitUntilElementExists(application.staticTexts["5 cards."])
  }
}

// Helpers
extension CommonplaceBookAppUITests {
  /// Waits for an element to exist in the hierarchy.
  /// - parameter element: The element to test for.
  /// - note: From http://masilotti.com/xctest-helpers/
  private func waitUntilElementExists(
    _ element: XCUIElement,
    file: String = #file,
    line: Int = #line
  ) {
    wait(
      for: NSPredicate(format: "exists == true"),
      evaluatedWith: element,
      message: "Failed to find \(element) after 5 seconds",
      file: file,
      line: line
    )
  }

  private func waitUntilElementEnabled(
    _ element: XCUIElement,
    file: String = #file,
    line: Int = #line
  ) {
    wait(
      for: NSPredicate(format: "isEnabled == true"),
      evaluatedWith: element,
      message: "\(element) did not become enabled",
      file: file,
      line: line
    )
  }

  private func wait(
    for predicate: NSPredicate,
    evaluatedWith object: Any,
    message: String,
    file: String = #file,
    line: Int = #line
  ) {
    expectation(for: predicate, evaluatedWith: object, handler: nil)
    waitForExpectations(timeout: 5) { (error) -> Void in
      if error != nil {
        self.recordFailure(
          withDescription: message,
          inFile: file,
          atLine: line,
          expected: true
        )
      }
    }
  }

  private func createDocument(with text: String) {
    application.buttons[Identifiers.newDocumentButton].tap()
    let editView = application.textViews[Identifiers.editDocumentView]
    waitUntilElementExists(editView)
    editView.typeText(text)
    editView.buttons[Identifiers.backButton].tap()
  }

  private func createDocument(with text: [String]) {
    application.buttons[Identifiers.newDocumentButton].tap()
    let editView = application.textViews[Identifiers.editDocumentView]
    waitUntilElementExists(editView)
    for line in text {
      editView.typeText(line)
    }
    editView.buttons[Identifiers.backButton].tap()
  }

  private func study(expectedCards: Int, noCardsLeft: Bool = true) {
    let studyButton = application.buttons[Identifiers.studyButton]
    waitUntilElementEnabled(studyButton)
    studyButton.tap()
    let currentCard = application.otherElements[Identifiers.currentCardView]
    let gotIt = application.buttons["Got it"]
    for _ in 0 ..< expectedCards {
      waitUntilElementExists(currentCard)
      currentCard.tap()
      waitUntilElementExists(gotIt)
      gotIt.tap()
    }
    if noCardsLeft {
      // After going through all clozes we should automatically go back to the document list.
      waitUntilElementExists(studyButton)
      wait(
        for: NSPredicate(format: "isEnabled == false"),
        evaluatedWith: studyButton,
        message: "Studying should be disabled"
      )
    }
  }
}
