// Copyright © 2019 Brian's Brain. All rights reserved.

import CocoaLumberjack
import CommonplaceBook
import FlashcardKit
import IGListKit
import MiniMarkdown
import UIKit

import enum TextBundleKit.Result

// TODO: Move to Swift.Result which has proper flatMap semantics
extension Result {
  /// Provides real "flatMap" semantics on TextBundleKit.Result; that type's `flatMap` is
  /// really `map` semantics.
  func realFlatMap<NewValue>(_ transform: (Value) -> Result<NewValue>) -> Result<NewValue> {
    switch self {
    case .success(let value):
      return transform(value)
    case .failure(let error):
      return .failure(error)
    }
  }
}

public protocol NoteBundleDocumentObserver: AnyObject {
  func noteBundleDocumentDidLoad(_ document: NoteBundleDocument)
  func noteBundleDocumentDidUpdatePages(_ document: NoteBundleDocument)
}

/// Any IGListKit ListAdapter can listen to notebook changes.
extension ListAdapter: NoteBundleDocumentObserver {
  public func noteBundleDocumentDidLoad(_ document: NoteBundleDocument) {
    performUpdates(animated: true)
  }

  public func noteBundleDocumentDidUpdatePages(_ document: NoteBundleDocument) {
    performUpdates(animated: true)
  }
}

/// Holds all of the information needed to conduct study sessions.
public final class NoteBundleDocument: UIDocument {

  public enum Error: Swift.Error {
    case documentKeyNotFound
  }

  public init(fileURL url: URL, parsingRules: ParsingRules) {
    self.parsingRules = parsingRules
    noteBundle = NoteBundle(parsingRules: parsingRules)
    super.init(fileURL: url)
  }

  private let parsingRules: ParsingRules

  /// Single structure holding all of the mutable data
  public private(set) var noteBundle: NoteBundle

  /// All things watching the document lifecycle.
  private var observers: [WeakObserver] = []

  private var loadPendingFilenames = Set<String>()

  /// Updates information about a page.
  /// - parameter fileMetadata: FileMetadata identifying the page in the metadata provider.
  /// - parameter metadataProvider: Container for pages.
  /// - parameter completion: Called after updating page properties. Will pass true if we had
  ///             to load properties from disk; false if we kept cached properties.
  public func updatePage(
    for fileMetadata: FileMetadata,
    in metadataProvider: FileMetadataProvider,
    completion: ((Bool) -> Void)?
  ) {
    assert(Thread.isMainThread)
    assert(documentState.intersection([.closed, .editingDisabled]).isEmpty)
    guard !loadPendingFilenames.contains(fileMetadata.fileName) else {
      completion?(false)
      return
    }
    if let existing = noteBundle.pageProperties[fileMetadata.fileName],
      existing.timestamp.closeEnough(to: fileMetadata.contentChangeDate) {
      completion?(false)
      return
    }
    loadPendingFilenames.insert(fileMetadata.fileName)
    metadataProvider.loadText(from: fileMetadata) { textResult in
      DispatchQueue.global(qos: .default).async {
        let propertiesResult = textResult.realFlatMap({ (text) -> Result<(NoteBundlePageProperties, ChallengeTemplateCollection)> in
          return Result {
            try self.noteBundle.extractPropertiesAndTemplates(from: text, loadedFrom: fileMetadata)
          }
        })
        DispatchQueue.main.async {
          switch propertiesResult {
          case .success(let tuple):
            let didChange = self.noteBundle.addChallengesFromPage(
              named: fileMetadata.fileName,
              pageProperties: tuple.0,
              challengeTemplates: tuple.1
            )
            if didChange {
              self.notifyObserversOfChange()
            }
          case .failure(let error):
            DDLogError("Unexpected error importing document: \(error)")
          }
          self.loadPendingFilenames.remove(fileMetadata.fileName)
          self.updateChangeCount(.done)
          completion?(true)
        }
      }
    }
  }

  /// Update the notebook with the result of a study session.
  ///
  /// - parameter studySession: The completed study session.
  /// - parameter date: The date the study session took place.
  public func updateStudySessionResults(_ studySession: StudySession, on date: Date = Date()) {
    assert(Thread.isMainThread)
    assert(documentState.intersection([.closed, .editingDisabled]).isEmpty)
    noteBundle.updateStudySessionResults(studySession, on: date)
    updateChangeCount(.done)
    self.notifyObserversOfChange()
  }

  public func deleteFileMetadata(_ fileMetadata: FileMetadata) {
    assertionFailure()
  }

  public func performRenames(_ desiredBaseNameForPage: [String: String]) throws {
    assertionFailure()
  }

  /// Loads document data.
  /// The document is a bundle of different data streams.
  public override func load(fromContents contents: Any, ofType typeName: String?) throws {
    guard let directory = contents as? FileWrapper else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: nil)
    }
    let newNoteBundle = try NoteBundle(parsingRules: parsingRules, fileWrapper: directory)
    self.noteBundle = newNoteBundle
    for wrapper in observers {
      wrapper.observer?.noteBundleDocumentDidLoad(self)
    }
  }

  /// Generates a bundle containing all of the current data.
  public override func contents(forType typeName: String) throws -> Any {
    let wrapper = try noteBundle.fileWrapper()
    return wrapper
  }
}

extension NoteBundleDocument: Observable {
  public func addObserver(_ observer: NoteBundleDocumentObserver) {
    observers.append(WeakObserver(observer))
  }

  public func removeObserver(_ observer: NoteBundleDocumentObserver) {
    observers.removeAll { wrapped -> Bool in
      wrapped.observer === observer
    }
  }

  private func notifyObserversOfChange() {
    for observerWrapper in observers {
      observerWrapper.observer?.noteBundleDocumentDidUpdatePages(self)
    }
  }
}

private struct WeakObserver {
  weak var observer: NoteBundleDocumentObserver?
  init(_ observer: NoteBundleDocumentObserver) { self.observer = observer }
}

private extension Date {
  /// True if the receiver and `other` are "close enough"
  func closeEnough(to other: Date) -> Bool {
    return abs(timeIntervalSince(other)) < 1
  }
}