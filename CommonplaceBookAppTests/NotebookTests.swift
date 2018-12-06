// Copyright © 2018 Brian's Brain. All rights reserved.

import CommonplaceBookApp
import MiniMarkdown
import TextBundleKit
import XCTest

final class NotebookTests: XCTestCase {
  var metadataProvider: TestMetadataProvider!

  override func setUp() {
    metadataProvider = TestMetadataProvider(
      fileInfo: [
        TestMetadataProvider.FileInfo(fileName: "page1.txt", contents: "#hashtag #test1"),
        TestMetadataProvider.FileInfo(fileName: "page2.txt", contents: "#hashtag #test2"),
        ]
    )
  }

  let parsingRules = ParsingRules()

  func testNotebookExtractsProperties() {
    let notebook = Notebook(
      parsingRules: parsingRules,
      metadataProvider: metadataProvider
    )
    XCTAssertEqual(notebook.pages.count, 2)
    wait(for: allPagesAreTruth, in: notebook)
    XCTAssertEqual(Set(notebook.pages["page1.txt"]!.value.hashtags), Set(["#hashtag", "#test1"]))
    XCTAssertEqual(Set(notebook.pages["page2.txt"]!.value.hashtags), Set(["#hashtag", "#test2"]))
  }

  func testNotebookHasJSONImmediately() {
    metadataProvider.addPropertiesCache()
    let notebook = Notebook(
      parsingRules: parsingRules,
      metadataProvider: metadataProvider
    )
    wait(for: noPagesArePlaceholders, in: notebook)
    XCTAssertEqual(Set(notebook.pages["page1.txt"]!.value.hashtags), Set(["#hashtag", "#test1"]))
    XCTAssertEqual(Set(notebook.pages["page2.txt"]!.value.hashtags), Set(["#hashtag", "#test2"]))
  }

  func testModifyDocumentWillUpdateProperties() {
    metadataProvider.addPropertiesCache()
    let notebook = Notebook(
      parsingRules: parsingRules,
      metadataProvider: metadataProvider
    )
    XCTAssert(metadataProvider.delegate === notebook)
    wait(for: allPagesAreTruth, in: notebook)
    metadataProvider.addFileInfo(
      TestMetadataProvider.FileInfo(fileName: "page1.txt", contents: "#newhashtag")
    )
    XCTAssertEqual(notebook.pages["page1.txt"]?.tag.rawValue, Tag.placeholder.rawValue)
    wait(for: allPagesAreTruth, in: notebook)
    XCTAssertEqual(notebook.pages["page1.txt"]!.value.hashtags, ["#newhashtag"])
  }

  func testUpdatingPropertiesUpdatesCache() {
    metadataProvider.addPropertiesCache()
    let notebook = Notebook(
      parsingRules: parsingRules,
      metadataProvider: metadataProvider
    )
    XCTAssert(metadataProvider.delegate === notebook)
    wait(for: allPagesAreTruth, in: notebook)
    let didSaveCache = expectation(description: "did save cache")
    metadataProvider.contentsChangeListener = { (name, text) in
      if name == Notebook.cachedPropertiesName {
        didSaveCache.fulfill()
      }
    }
    metadataProvider.addFileInfo(
      TestMetadataProvider.FileInfo(fileName: "page1.txt", contents: "#newhashtag")
    )
    waitForExpectations(timeout: 3, handler: nil)
    let deserializedPages = Notebook.pagesDictionary(
      from: metadataProvider.fileContents[Notebook.cachedPropertiesName]!,
      tag: .fromCache
    )
    XCTAssertEqual(deserializedPages["page1.txt"]?.value.hashtags, ["#newhashtag"])
  }

  // MARK: - Helpers

  private let allPagesAreTruth = NotebookTests.notebookPagesAllHaveTag(.truth)

  private let allPagesAreCached = NotebookTests.notebookPagesAllHaveTag(.fromCache)

  private let noPagesArePlaceholders = NotebookTests.notebookPagesNoneHaveTag(.placeholder)

  private static func notebookPagesAllHaveTag(_ tag: Tag) -> (Notebook) -> Bool {
    return { (notebook) in
      return notebook.pages.allSatisfy( { $1.tag == tag })
    }
  }

  private static func notebookPagesNoneHaveTag(_ tag: Tag) -> (Notebook) -> Bool {
    return { (notebook) in
      return notebook.pages.allSatisfy( { $1.tag != tag })
    }
  }

  private func wait(for condition: @escaping (Notebook) -> Bool, in notebook: Notebook) {
    if condition(notebook) { return }
    let conditionSatisfied = expectation(description: "generic condition")
    let notebookListener = TestListener { (notebook) in
      print("\(notebook.pages.values.map { $0.tag })")
      if condition(notebook) {
        conditionSatisfied.fulfill()
      }
    }
    notebook.addListener(notebookListener)
    waitForExpectations(timeout: 3, handler: nil)
  }
}

final class TestListener: NotebookPageChangeListener {

  init(block: @escaping (Notebook) -> Void) { self.block = block }

  let block: (Notebook) -> Void

  func notebookPagesDidChange(_ notebook: Notebook) {
    block(notebook)
  }
}
