// Copyright © 2019 Brian's Brain. All rights reserved.

import CocoaLumberjack
import IGListKit
import MiniMarkdown
import UIKit

public protocol NoteArchiveDocumentObserver: AnyObject {
  func noteArchiveDocument(
    _ document: NoteArchiveDocument,
    didUpdatePageProperties properties: [String: PageProperties]
  )
}

extension ListAdapter: NoteArchiveDocumentObserver {
  public func noteArchiveDocument(
    _ document: NoteArchiveDocument,
    didUpdatePageProperties properties: [String: PageProperties]
  ) {
    performUpdates(animated: true)
  }
}

public final class NoteArchiveDocument: UIDocument {
  public init(fileURL url: URL, parsingRules: ParsingRules) {
    self.parsingRules = parsingRules
    self.noteArchive = NoteArchive(parsingRules: parsingRules)
    super.init(fileURL: url)
  }

  /// How to parse Markdown in the snippets
  public let parsingRules: ParsingRules

  /// Top-level FileWrapper for our contents
  private var topLevelFileWrapper: FileWrapper?

  /// The actual document contents.
  internal var noteArchive: NoteArchive

  /// Protects noteArchive.
  internal let noteArchiveQueue = DispatchQueue(label: "org.brians-brain.note-archive-document")

  internal var studyLog = StudyLog()

  private let challengeTemplateCache = NSCache<NSString, ChallengeTemplate>()

  /// The observers.
  private var observers: [WeakObserver] = []

  /// Accessor for the page properties.
  public var pageProperties: [String: PageProperties] {
    return noteArchiveQueue.sync {
      noteArchive.pageProperties
    }
  }

  /// Holds page contents in memory until we have a chance to save.
  private var modifiedPageContents: [String: String] = [:]

  public func currentTextContents(for pageIdentifier: String) throws -> String {
    assert(Thread.isMainThread)
    if let inMemoryContents = modifiedPageContents[pageIdentifier] {
      return inMemoryContents
    }
    return try noteArchiveQueue.sync {
      try noteArchive.currentText(for: pageIdentifier)
    }
  }

  public func changeTextContents(for pageIdentifier: String, to text: String) {
    assert(Thread.isMainThread)
    modifiedPageContents[pageIdentifier] = text
    invalidateSavedSnippets()
  }

  public func deletePage(pageIdentifier: String) {
    assertionFailure("Not implemented")
  }

  private enum BundleWrapperKey {
    static let snippets = "text.snippets"
    static let studyLog = "study.log"
  }

  /// Deserialize `noteArchive` from `contents`
  /// - precondition: `contents` is a directory FileWrapper with a "text.snippets" regular file
  /// - throws: NSError in the NoteArchiveDocument domain on any error
  public override func load(fromContents contents: Any, ofType typeName: String?) throws {
    guard let wrapper = contents as? FileWrapper, wrapper.isDirectory else {
      throw error(for: .unexpectedContentType)
    }
    topLevelFileWrapper = wrapper
    guard
      let data = wrapper.fileWrappers?[BundleWrapperKey.snippets]?.regularFileContents,
      let text = String(data: data, encoding: .utf8) else {
        // Is this an error? Or expected for a new document?
        return
    }
    if let logData = wrapper.fileWrappers?[BundleWrapperKey.studyLog]?.regularFileContents,
      let logText = String(data: logData, encoding: .utf8),
      let studyLog = StudyLog(logText) {
      self.studyLog = studyLog
    }
    do {
      let pageProperties = try noteArchiveQueue.sync { () -> [String: PageProperties] in
        noteArchive = try NoteArchive(parsingRules: parsingRules, textSerialization: text)
        return noteArchive.pageProperties
      }
      DDLogInfo("Loaded \(pageProperties.count) pages")
      notifyObservers(of: pageProperties)
    } catch {
      throw wrapError(code: .textSnippetsDeserializeError, innerError: error)
    }
  }

  /// Serialize `noteArchive` to `topLevelFileWrapper` and return `topLevelFileWrapper` for saving
  public override func contents(forType typeName: String) throws -> Any {
    let topLevelFileWrapper = self.topLevelFileWrapper
      ?? FileWrapper(directoryWithFileWrappers: [:])
    precondition(topLevelFileWrapper.isDirectory)
    var shouldNotify = false
    if topLevelFileWrapper.fileWrappers![BundleWrapperKey.snippets] == nil {
      let now = Date()
      try noteArchiveQueue.sync {
        for (pageIdentifier, modifiedText) in modifiedPageContents {
          try self.noteArchive.updateText(
            for: pageIdentifier,
            to: modifiedText,
            contentChangeTime: now,
            versionTimestamp: now
          )
          shouldNotify = true
        }
        modifiedPageContents.removeAll()
      }
      topLevelFileWrapper.addFileWrapper(textSnippetsFileWrapper())
    }
    if topLevelFileWrapper.fileWrappers![BundleWrapperKey.studyLog] == nil {
      let logWrapper = FileWrapper(
        regularFileWithContents: studyLog.description.data(using: .utf8)!
      )
      logWrapper.preferredFilename = BundleWrapperKey.studyLog
      topLevelFileWrapper.addFileWrapper(logWrapper)
    }
    self.topLevelFileWrapper = topLevelFileWrapper
    DDLogInfo("Saving: \(topLevelFileWrapper.fileWrappers!.keys)")
    if shouldNotify {
      notifyObservers(of: pageProperties)
    }
    return topLevelFileWrapper
  }

  /// Lets the UIDocument infrastructure know we have content to save, and also
  /// discards our in-memory representation of the snippet file wrapper.
  internal func invalidateSavedSnippets() {
    if let topLevelFileWrapper = topLevelFileWrapper,
      let archiveWrapper = topLevelFileWrapper.fileWrappers![BundleWrapperKey.snippets] {
      topLevelFileWrapper.removeFileWrapper(archiveWrapper)
    }
    updateChangeCount(.done)
  }

  internal func invalidateSavedStudyLog() {
    if let topLevelFileWrapper = topLevelFileWrapper,
      let archiveWrapper = topLevelFileWrapper.fileWrappers![BundleWrapperKey.studyLog] {
      topLevelFileWrapper.removeFileWrapper(archiveWrapper)
    }
    updateChangeCount(.done)
  }
}

/// Observing.
public extension NoteArchiveDocument {
  private struct WeakObserver {
    weak var observer: NoteArchiveDocumentObserver?
    init(_ observer: NoteArchiveDocumentObserver) { self.observer = observer }
  }

  func addObserver(_ observer: NoteArchiveDocumentObserver) {
    assert(Thread.isMainThread)
    observers.append(WeakObserver(observer))
  }

  func removeObserver(_ observer: NoteArchiveDocumentObserver) {
    assert(Thread.isMainThread)
    observers.removeAll(where: { $0.observer === observer })
  }

  internal func notifyObservers(of pageProperties: [String: PageProperties]) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async {
        self.notifyObservers(of: pageProperties)
      }
      return
    }
    for observerWrapper in observers {
      observerWrapper.observer?.noteArchiveDocument(self, didUpdatePageProperties: pageProperties)
    }
  }
}

private extension NoteArchiveDocument {
  /// Returns a FileWrapper containing the serialized text snippets
  func textSnippetsFileWrapper() -> FileWrapper {
    let text = noteArchiveQueue.sync {
      noteArchive.textSerialized()
    }
    let fileWrapper = FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    fileWrapper.preferredFilename = BundleWrapperKey.snippets
    return fileWrapper
  }
}

/// Making NSErrors...
public extension NoteArchiveDocument {
  static let errorDomain = "NoteArchiveDocument"

  enum ErrorCode: String, CaseIterable {
    case textSnippetsDeserializeError = "Unexpected error deserializing text.snippets"
    case unexpectedContentType = "Unexpected file content type"
  }

  /// Constructs an NSError based upon the the `ErrorCode` string value & index.
  func error(for code: ErrorCode) -> NSError {
    let index = ErrorCode.allCases.firstIndex(of: code)!
    return NSError(
      domain: NoteArchiveDocument.errorDomain,
      code: index,
      userInfo: [NSLocalizedDescriptionKey: code.rawValue]
    )
  }

  /// Constructs an NSError that wraps another arbitrary error.
  func wrapError(code: ErrorCode, innerError: Error) -> NSError {
    let index = ErrorCode.allCases.firstIndex(of: code)!
    return NSError(
      domain: NoteArchiveDocument.errorDomain,
      code: index,
      userInfo: [
        NSLocalizedDescriptionKey: code.rawValue,
        "innerError": innerError,
      ]
    )
  }
}

// MARK: - Study sessions
public extension NoteArchiveDocument {
  func studySession(
    filter: ((String, PageProperties) -> Bool)? = nil,
    date: Date = Date()
  ) -> StudySession {
    let filter = filter ?? { _, _ in true }
    let suppressionDates = studyLog.identifierSuppressionDates()
    return noteArchiveQueue.sync {
      return noteArchive.pageProperties
        .filter { filter($0.key, $0.value) }
        .map { (name, reviewProperties) -> StudySession in
          let challengeTemplates = reviewProperties.cardTemplates
            .compactMap { keyString -> ChallengeTemplate? in
              guard let key = ChallengeTemplateArchiveKey(keyString) else {
                DDLogError("Expected a challenge key: \(keyString)")
                return nil
              }
              if let cachedTemplate = challengeTemplateCache.object(forKey: keyString as NSString) {
                return cachedTemplate
              }
              do {
                let template = try noteArchive.challengeTemplate(for: key)
                template.templateIdentifier = key.digest
                challengeTemplateCache.setObject(template, forKey: keyString as NSString)
                return template
              } catch {
                DDLogError("Unexpected error getting challenge template: \(error)")
                return nil
              }
            }
          // TODO: Filter down to eligible cards
          let eligibleCards = challengeTemplates.cards
            .filter { challenge -> Bool in
              guard let suppressionDate = suppressionDates[challenge.challengeIdentifier] else {
                return true
              }
              return date >= suppressionDate
            }
          return StudySession(
            eligibleCards,
            properties: CardDocumentProperties(
              documentName: name,
              attributionMarkdown: reviewProperties.title,
              parsingRules: self.parsingRules
            )
          )
        }
        .reduce(into: StudySession(), { $0 += $1 })
    }
  }

  /// Update the notebook with the result of a study session.
  ///
  /// - parameter studySession: The completed study session.
  /// - parameter date: The date the study session took place.
  func updateStudySessionResults(_ studySession: StudySession, on date: Date = Date()) {
    studyLog.updateStudySessionResults(studySession, on: date)
    invalidateSavedStudyLog()
    notifyObservers(of: pageProperties)
  }
}
