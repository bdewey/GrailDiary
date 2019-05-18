// Copyright © 2019 Brian's Brain. All rights reserved.

import CocoaLumberjack
import FlashcardKit
import MiniMarkdown
import UIKit

public protocol StudyMetadataDocumentObserver: AnyObject {
  func studyMetadataDocumentDidLoad(_ document: StudyMetadataDocument)
}

/// Holds all of the information needed to conduct study sessions.
public final class StudyMetadataDocument: UIDocument {

  public enum Error: Swift.Error {
    case documentKeyNotFound
  }

  public init(fileURL url: URL, parsingRules: ParsingRules) {
    self.parsingRules = parsingRules
    super.init(fileURL: url)
  }

  private let parsingRules: ParsingRules

  /// All notebook pages we know about. Maps the lastPathComponent of the file to relevant properties.
  public private(set) var pageProperties: [String: ReviewPageProperties] = [:]

  /// All challenge templates across all pages.
  public private(set) var challengeTemplates = ChallengeTemplateCollection()

  /// Logs all changes.
  public private(set) var log = [ChangeRecord]()

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
    guard !loadPendingFilenames.contains(fileMetadata.fileName) else {
      completion?(false)
      return
    }
    if let existing = pageProperties[fileMetadata.fileName],
      existing.timestamp.closeEnough(to: fileMetadata.contentChangeDate) {
      completion?(false)
      return
    }
    guard let document = metadataProvider.editableDocument(for: fileMetadata) else {
      completion?(false)
      return
    }
    loadPendingFilenames.insert(fileMetadata.fileName)
    document.open { success in
      guard success else { completion?(false); return }
      let textResult = document.currentTextResult
      document.close(completionHandler: nil)
      DispatchQueue.global(qos: .default).async {
        let result = textResult.flatMap({ taggedText -> (ReviewPageProperties, ChallengeTemplateCollection) in
          let digest = taggedText.value.sha1Digest()
          let nodes = self.parsingRules.parse(taggedText.value)
          // TODO: Bubble up the error
          let challengeTemplates = (try? nodes.challengeTemplates()) ?? ChallengeTemplateCollection()
          let properties = ReviewPageProperties(
            sha1Digest: digest,
            timestamp: fileMetadata.contentChangeDate,
            hashtags: nodes.hashtags,
            title: nodes.title,
            cardTemplates: challengeTemplates.keys
          )
          return (properties, challengeTemplates)
        })
        DispatchQueue.main.async {
          switch result {
          case .success(let tuple):
            self.injest(fileName: fileMetadata.fileName, pageProperties: tuple.0, challengeTemplates: tuple.1)
          case .failure(let error):
            DDLogError("Unexpected error importing document: \(error)")
          }
          self.loadPendingFilenames.remove(fileMetadata.fileName)
          completion?(true)
        }
      }
    }
  }

  private func injest(
    fileName: String,
    pageProperties: ReviewPageProperties,
    challengeTemplates: ChallengeTemplateCollection
  ) {
    assert(Thread.isMainThread)
    if let existing = self.pageProperties[fileName],
      existing.sha1Digest == pageProperties.sha1Digest {
      DDLogInfo("Skipping \(fileName) -- already have properties for \(pageProperties.sha1Digest)")
      return
    }
    log.append(ChangeRecord(timestamp: Date(), change: .addedPage(name: fileName, digest: pageProperties.sha1Digest)))
    self.pageProperties[fileName] = pageProperties
    let addedTemplateKeys = self.challengeTemplates.merge(challengeTemplates)
    for key in addedTemplateKeys {
      log.append(ChangeRecord(timestamp: Date(), change: .addedChallengeTemplate(id: key)))
    }
    DDLogInfo("Added information about \(addedTemplateKeys.count) challenges from \(fileName) (\(pageProperties.sha1Digest))")
    updateChangeCount(.done)
  }

  /// Inserts a ChallengeTemplate into the document.
  /// - returns: The key that can be used to retrieve this template from `challengeTemplates`
  private func insert(_ challengeTemplate: ChallengeTemplate) throws -> String {
    assert(Thread.isMainThread)
    let (key, didChange) = try challengeTemplates.insert(challengeTemplate)
    if didChange {
      updateChangeCount(.done)
      log.append(ChangeRecord(timestamp: Date(), change: .addedChallengeTemplate(id: key)))
    }
    return key
  }

  /// Loads document data.
  /// The document is a bundle of different data streams.
  public override func load(fromContents contents: Any, ofType typeName: String?) throws {
    guard let directory = contents as? FileWrapper else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: nil)
    }
    challengeTemplates = try directory.loadChallengeTemplateCollection(using: parsingRules)
    log = try directory.loadLog()
    pageProperties = try directory.loadPages()
    for wrapper in observers {
      wrapper.observer?.studyMetadataDocumentDidLoad(self)
    }
  }

  /// Generates a bundle containing all of the current data.
  public override func contents(forType typeName: String) throws -> Any {
    let logString = log.map { $0.description }.joined(separator: "\n")
    let logWrapper = FileWrapper(regularFileWithContents: logString.data(using: .utf8)!)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let pageData = try encoder.encode(pageProperties)
    return FileWrapper(
      directoryWithFileWrappers: [
        BundleKey.challengeTemplates: challengeTemplates.fileWrapper(),
        BundleKey.log: logWrapper,
        BundleKey.pages: FileWrapper(regularFileWithContents: pageData),
      ]
    )
  }
}

extension StudyMetadataDocument: Observable {
  public func addObserver(_ observer: StudyMetadataDocumentObserver) {
    observers.append(WeakObserver(observer))
  }

  public func removeObserver(_ observer: StudyMetadataDocumentObserver) {
    observers.removeAll { wrapped -> Bool in
      wrapped.observer === observer
    }
  }
}

private extension String {
  func removingPrefix(_ prefix: String) -> Substring? {
    guard hasPrefix(prefix) else { return nil }
    return suffix(from: index(startIndex, offsetBy: prefix.count))
  }
}

public extension StudyMetadataDocument {
  enum Change: LosslessStringConvertible {

    /// We added a template to the document.
    case addedChallengeTemplate(id: String)

    case addedPage(name: String, digest: String)

    /// Decode a change from a string.
    public init?(_ description: String) {
      if let digest = description.removingPrefix(Prefix.addChallengeTemplate) {
        self = .addedChallengeTemplate(id: String(digest))
      } else if let digestAndName = description.removingPrefix(Prefix.addPage) {
        let components = digestAndName.split(separator: " ")
        if components.count > 1 {
          let name = String(components[1...].joined(separator: " "))
          self = .addedPage(name: name, digest: String(components[0]))
        } else {
          return nil
        }
      } else {
        return nil
      }
    }

    /// Turn a change into a string.
    public var description: String {
      switch self {
      case .addedChallengeTemplate(let digest):
        return Prefix.addChallengeTemplate + digest
      case .addedPage(name: let name, digest: let digest):
        return Prefix.addPage + digest + " " + name
      }
    }

    private enum Prefix {
      static let addChallengeTemplate = "add-template        "
      static let addPage              = "add-page            "
    }
  }

  struct ChangeRecord: LosslessStringConvertible {
    let timestamp: Date
    let change: Change

    public init(timestamp: Date, change: Change) {
      self.timestamp = timestamp
      self.change = change
    }

    public init?(_ description: String) {
      guard let firstWhitespace = description.firstIndex(of: " ") else {
        return nil
      }
      let dateSlice = description[description.startIndex ..< firstWhitespace]
      let skippingWhitespace = description.index(after: firstWhitespace)
      let changeSlice = description[skippingWhitespace...]
      guard let timestamp = ISO8601DateFormatter().date(from: String(dateSlice)),
        let change = Change(String(changeSlice)) else {
          return nil
      }
      self.timestamp = timestamp
      self.change = change
    }

    public var description: String {
      return ISO8601DateFormatter().string(from: timestamp) + " " + change.description
    }
  }
}

/// The names of the different streams inside our bundle.
private enum BundleKey {
  static let challengeTemplates = "challenge-templates.tdat"
  static let log = "change.log"
  static let pages = "pages.json"
}

/// Loading properties.
private extension FileWrapper {
  func loadChallengeTemplateCollection(using parsingRules: ParsingRules) throws -> ChallengeTemplateCollection {
    guard
      let wrapper = fileWrappers?[BundleKey.challengeTemplates],
      let data = wrapper.regularFileContents
      else {
        throw StudyMetadataDocument.Error.documentKeyNotFound
    }
    return try ChallengeTemplateCollection(parsingRules: parsingRules, data: data)
  }

  func loadLog() throws -> [StudyMetadataDocument.ChangeRecord] {
    guard let wrapper = fileWrappers?[BundleKey.log],
      let data = wrapper.regularFileContents,
      let str = String(data: data, encoding: .utf8) else {
        throw StudyMetadataDocument.Error.documentKeyNotFound
    }
    return str.split(separator: "\n").compactMap { StudyMetadataDocument.ChangeRecord(String($0)) }
  }

  func loadPages() throws -> [String: ReviewPageProperties] {
    guard
      let wrapper = fileWrappers?[BundleKey.pages],
      let data = wrapper.regularFileContents
      else {
        throw StudyMetadataDocument.Error.documentKeyNotFound
    }
    return try JSONDecoder().decode([String: ReviewPageProperties].self, from: data)
  }
}

private extension ChallengeTemplateCollection {
  func fileWrapper() -> FileWrapper {
    return FileWrapper(regularFileWithContents: data())
  }
}

private struct WeakObserver {
  weak var observer: StudyMetadataDocumentObserver?
  init(_ observer: StudyMetadataDocumentObserver) { self.observer = observer }
}

private extension Date {
  /// True if the receiver and `other` are "close enough"
  func closeEnough(to other: Date) -> Bool {
    return abs(timeIntervalSince(other)) < 1
  }
}

