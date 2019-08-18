// Copyright © 2017-present Brian's Brain. All rights reserved.

import CocoaLumberjack
import CoreSpotlight
import DataCompression
import MiniMarkdown
import MobileCoreServices
import UIKit

public protocol NoteArchiveDocumentObserver: AnyObject {
  func noteArchiveDocument(
    _ document: NoteArchiveDocument,
    didUpdatePageProperties properties: [String: PageProperties]
  )
}

/// A UIDocument that contains a NoteArchive and a StudyLog.
public final class NoteArchiveDocument: UIDocument {
  /// Designated initializer.
  /// - parameter fileURL: The URL of the document
  /// - parameter parsingRules: Defines how to parse markdown inside the notes
  public init(fileURL url: URL, parsingRules: ParsingRules) {
    self.parsingRules = parsingRules
    self.noteArchive = NoteArchive(parsingRules: parsingRules)
    super.init(fileURL: url)
  }

  /// How to parse Markdown in the snippets
  public let parsingRules: ParsingRules

  /// Top-level FileWrapper for our contents
  private var topLevelFileWrapper = FileWrapper(directoryWithFileWrappers: [:])

  /// The actual document contents.
  internal var noteArchive: NoteArchive

  /// Protects noteArchive.
  internal let noteArchiveQueue = DispatchQueue(label: "org.brians-brain.note-archive-document")

  /// Holds the outcome of every study session.
  public internal(set) var studyLog = StudyLog()

  /// If there is every an I/O error, this contains it.
  public private(set) var previousError: Error?

  private let challengeTemplateCache = NSCache<NSString, ChallengeTemplate>()

  /// The observers.
  private var observers: [WeakObserver] = []

  /// Accessor for the page properties.
  public var pageProperties: [String: PageProperties] {
    return noteArchiveQueue.sync {
      noteArchive.pageProperties
    }
  }

  /// All hashtags used across all pages, sorted.
  public var hashtags: [String] {
    let hashtags = pageProperties.values.reduce(into: Set<String>()) { hashtags, props in
      hashtags.formUnion(props.hashtags)
    }
    return Array(hashtags).sorted()
  }

  public func currentTextContents(for pageIdentifier: String) throws -> String {
    assert(Thread.isMainThread)
    return try noteArchiveQueue.sync {
      try noteArchive.currentText(for: pageIdentifier)
    }
  }

  public func changeTextContents(for pageIdentifier: String, to text: String) {
    assert(Thread.isMainThread)
    noteArchiveQueue.sync {
      noteArchive.updateText(for: pageIdentifier, to: text, contentChangeTime: Date())
    }
    invalidateSavedSnippets()
    schedulePropertyBatchUpdate()
  }

  private var propertyBatchUpdateTimer: Timer?

  private func schedulePropertyBatchUpdate() {
    guard propertyBatchUpdateTimer == nil else { return }
    propertyBatchUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { _ in
      let count = self.noteArchiveQueue.sync {
        self.noteArchive.batchUpdatePageProperties()
      }
      // swiftlint:disable:next empty_count
      if count > 0 {
        self.notifyObservers(of: self.pageProperties)
      }
      self.propertyBatchUpdateTimer = nil
    })
  }

  public func deletePage(pageIdentifier: String) throws {
    noteArchiveQueue.sync {
      noteArchive.removeNote(for: pageIdentifier)
    }
    CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [pageIdentifier], completionHandler: nil)
    invalidateSavedSnippets()
    notifyObservers(of: pageProperties)
  }

  private enum BundleWrapperKey {
    static let compressedSnippets = "text.snippets.gz"
    static let compressedStudyLog = "study.log.gz"
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
    studyLog = NoteArchiveDocument.loadStudyLog(from: wrapper)
    do {
      let noteArchive = try NoteArchiveDocument.loadNoteArchive(
        from: wrapper,
        parsingRules: parsingRules
      )
      noteArchive.addToSpotlight()
      let pageProperties = noteArchive.pageProperties
      noteArchiveQueue.sync { self.noteArchive = noteArchive }
      DDLogInfo("Loaded \(pageProperties.count) pages")
      notifyObservers(of: pageProperties)
    } catch {
      throw wrapError(code: .textSnippetsDeserializeError, innerError: error)
    }
  }

  /// Serialize `noteArchive` to `topLevelFileWrapper` and return `topLevelFileWrapper` for saving
  public override func contents(forType typeName: String) throws -> Any {
    precondition(topLevelFileWrapper.isDirectory)
    if topLevelFileWrapper.fileWrappers![BundleWrapperKey.compressedSnippets] == nil {
      topLevelFileWrapper.addFileWrapper(try compressedSnippetsFileWrapper())
    }
    if topLevelFileWrapper.fileWrappers![BundleWrapperKey.compressedStudyLog] == nil {
      guard let compressedLog = studyLog.description.data(using: .utf8)!.gzip() else {
        throw error(for: .couldNotCompressStudyLog)
      }
      let logWrapper = FileWrapper(
        regularFileWithContents: compressedLog
      )
      logWrapper.preferredFilename = BundleWrapperKey.compressedStudyLog
      topLevelFileWrapper.addFileWrapper(logWrapper)
    }
    purgeUnneededWrappers(from: topLevelFileWrapper)
    DDLogInfo("Saving: \(topLevelFileWrapper.fileWrappers!.keys)")
    return topLevelFileWrapper
  }

  public override func handleError(_ error: Error, userInteractionPermitted: Bool) {
    previousError = error
    super.handleError(error, userInteractionPermitted: userInteractionPermitted)
  }

  /// Lets the UIDocument infrastructure know we have content to save, and also
  /// discards our in-memory representation of the snippet file wrapper.
  internal func invalidateSavedSnippets() {
    if let compressedWrapper = topLevelFileWrapper.fileWrappers![BundleWrapperKey.compressedSnippets] {
      topLevelFileWrapper.removeFileWrapper(compressedWrapper)
    }
    updateChangeCount(.done)
  }

  internal func invalidateSavedStudyLog() {
    if let archiveWrapper = topLevelFileWrapper.fileWrappers![BundleWrapperKey.compressedStudyLog] {
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

/// Load / save support
private extension NoteArchiveDocument {
  static func loadNoteArchive(
    from wrapper: FileWrapper,
    parsingRules: ParsingRules
  ) throws -> NoteArchive {
    let maybeData = wrapper.fileWrappers?[BundleWrapperKey.compressedSnippets]?.regularFileContents?.gunzip()
      ?? wrapper.fileWrappers?[BundleWrapperKey.snippets]?.regularFileContents
    guard
      let data = maybeData,
      let text = String(data: data, encoding: .utf8) else {
      // Is this an error? Or expected for a new document?
      return NoteArchive(parsingRules: parsingRules)
    }
    return try NoteArchive(parsingRules: parsingRules, textSerialization: text)
  }

  static func loadStudyLog(from wrapper: FileWrapper) -> StudyLog {
    let maybeData = wrapper.fileWrappers?[BundleWrapperKey.compressedStudyLog]?.regularFileContents?.gunzip()
      ?? wrapper.fileWrappers?[BundleWrapperKey.studyLog]?.regularFileContents
    guard let logData = maybeData,
      let logText = String(data: logData, encoding: .utf8),
      let studyLog = StudyLog(logText) else {
      return StudyLog()
    }
    return studyLog
  }

  func compressedSnippetsFileWrapper() throws -> FileWrapper {
    let text = try noteArchiveQueue.sync { () -> String in
      try noteArchive.archivePageManifestVersion(timestamp: Date())
      return noteArchive.textSerialized()
    }
    guard let compressed = text.data(using: .utf8)!.gzip() else {
      throw error(for: .couldNotCompressArchive)
    }
    let compressedWrapper = FileWrapper(regularFileWithContents: compressed)
    compressedWrapper.preferredFilename = BundleWrapperKey.compressedSnippets
    return compressedWrapper
  }

  /// Removes unneeded data file wrappers from `directoryWrapper`
  func purgeUnneededWrappers(from directoryWrapper: FileWrapper) {
    precondition(directoryWrapper.isDirectory)
    let unneededKeys = Set(directoryWrapper.fileWrappers!.keys)
      .subtracting([BundleWrapperKey.compressedStudyLog, BundleWrapperKey.compressedSnippets])
    for key in unneededKeys {
      directoryWrapper.removeFileWrapper(directoryWrapper.fileWrappers![key]!)
    }
  }
}

/// Making NSErrors...
public extension NoteArchiveDocument {
  static let errorDomain = "NoteArchiveDocument"

  enum ErrorCode: String, CaseIterable {
    case couldNotCompressArchive = "Could not compress text.snippets"
    case couldNotCompressStudyLog = "Could not compress study.log"
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
      noteArchive.pageProperties
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
        .reduce(into: StudySession()) { $0 += $1 }
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

// MARK: - MarkdownEditingTextViewImageStoring

extension NoteArchiveDocument: MarkdownEditingTextViewImageStoring {
  public func markdownEditingTextView(
    _ textView: MarkdownEditingTextView,
    store imageData: Data,
    suffix: String
  ) -> String {
    let hash = imageData.sha1Digest()
    DDLogError("Need to implement storage for \(hash)")
    return "\(hash).\(suffix)"
  }
}
