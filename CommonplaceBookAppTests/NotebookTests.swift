// Copyright © 2018 Brian's Brain. All rights reserved.

import CommonplaceBookApp
import MiniMarkdown
import XCTest

final class NotebookTests: XCTestCase {
  let metadataProvider = TestMetadataProvider(
    fileInfo: [
      TestMetadataProvider.FileInfo(fileName: "page1.txt", contents: "#hashtag #test1"),
      TestMetadataProvider.FileInfo(fileName: "page2.txt", contents: "#hashtag #test2"),
      ]
  )

  func testNotebookExtractsProperties() {
    let notebook = Notebook(
      parsingRules: ParsingRules(),
      metadataProvider: metadataProvider
    )
    XCTAssertEqual(notebook.pages.count, 2)
    let didGetNotified = expectation(description: "did get notified")

    // When we don't have persisted properties, we read and update each file in a serial
    // background queue. Thus, two notifications before we know we know we have the hashtags
    var expectedNotifications = 2
    let notebookListener = TestListener {
      expectedNotifications -= 1
      if expectedNotifications == 0 { didGetNotified.fulfill() }
    }
    notebook.addListener(notebookListener)
    waitForExpectations(timeout: 3, handler: nil)
    XCTAssertEqual(Set(notebook.pages["page1.txt"]!.hashtags), Set(["#hashtag", "#test1"]))
    XCTAssertEqual(Set(notebook.pages["page2.txt"]!.hashtags), Set(["#hashtag", "#test2"]))
  }

  func testNotebookHasJSONImmediately() {
    var metadataProvider = self.metadataProvider
    let cachedProperties = metadataProvider.documentPropertiesJSON
    metadataProvider.addFileInfo(
      TestMetadataProvider.FileInfo(
        fileName: Notebook.cachedPropertiesName,
        contents: cachedProperties
      )
    )
    let notebook = Notebook(
      parsingRules: ParsingRules(),
      metadataProvider: metadataProvider
    )
    XCTAssertEqual(notebook.pages.count, 2)
    // When we don't have persisted properties, we read and update each file in a serial
    // background queue. Thus, two notifications before we know we know we have the hashtags
    let didGetNotified = expectation(description: "did get notified")
    var expectedNotifications = 1
    let notebookListener = TestListener {
      expectedNotifications -= 1
      if expectedNotifications == 0 { didGetNotified.fulfill() }
    }
    notebook.addListener(notebookListener)
    waitForExpectations(timeout: 3, handler: nil)
    XCTAssertEqual(Set(notebook.pages["page1.txt"]!.hashtags), Set(["#hashtag", "#test1"]))
    XCTAssertEqual(Set(notebook.pages["page2.txt"]!.hashtags), Set(["#hashtag", "#test2"]))
  }
}

final class TestListener: NotebookPageChangeListener {

  init(block: @escaping () -> Void) { self.block = block }

  let block: () -> Void

  func notebookPagesDidChange(_ index: Notebook) {
    block()
  }
}
