// Copyright © 2017-present Brian's Brain. All rights reserved.

import CommonplaceBookApp
import Foundation
import MiniMarkdown

/// Serves in-memory copy of FileMetadata object that are backed by TestEditableDocument
/// instances.
final class TestMetadataProvider: FileMetadataProvider {
  /// A subset of `FileMetadata` that also includes file contents.
  struct FileInfo {
    let fileName: String
    let contents: String
  }

  /// Designated initializer.
  ///
  /// - parameter fileMetadata: The file metadata in this collection.
  init(fileInfo: [FileInfo], parsingRules: ParsingRules) {
    self.fileNameToMetadata = fileInfo.reduce(
      into: [String: FileMetadata](), { $0[$1.fileName] = FileMetadata(fileName: $1.fileName) }
    )
    self.fileContents = fileInfo.reduce(into: [String: String]()) { $0[$1.fileName] = $1.contents }
    self.parsingRules = parsingRules
  }

  func addFileInfo(_ fileInfo: FileInfo) {
    if var existingMetadata = fileNameToMetadata[fileInfo.fileName] {
      existingMetadata.contentChangeDate.addTimeInterval(3)
      fileNameToMetadata[fileInfo.fileName] = existingMetadata
    } else {
      fileNameToMetadata[fileInfo.fileName] = FileMetadata(fileName: fileInfo.fileName)
    }
    fileContents[fileInfo.fileName] = fileInfo.contents
    delegate?.fileMetadataProvider(self, didUpdate: fileMetadata)
  }

  /// A fake URL for this container.
  let container = URL(string: "test://metadata")!

  let parsingRules: ParsingRules

  /// Map of file name to file metadata (includes things like modified time)
  var fileNameToMetadata: [String: FileMetadata]

  var fileMetadata: [FileMetadata] { return Array(fileNameToMetadata.values) }

  func queryForCurrentFileMetadata(completion: @escaping ([FileMetadata]) -> Void) {
    completion(fileMetadata)
  }

  /// Map of file name to file contents
  var fileContents: [String: String]

  var contentsChangeListener: ((String, String) -> Void)?

  /// A delegate to notify in the event of changes.
  /// - note: Currently unused as the metadata in this collection are immutable.
  weak var delegate: FileMetadataProviderDelegate?

  func data(for fileMetadata: FileMetadata) throws -> Data {
    guard let contents = fileContents[fileMetadata.fileName] else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
    }
    return contents.data(using: .utf8)!
  }

  func text(for fileMetadata: FileMetadata) throws -> String {
    guard let contents = fileContents[fileMetadata.fileName] else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
    }
    return contents
  }

  func delete(_ metadata: FileMetadata) throws {
    fileNameToMetadata[metadata.fileName] = nil
    fileContents[metadata.fileName] = nil
  }

  func itemExists(with pathComponent: String) throws -> Bool {
    return fileNameToMetadata[pathComponent] != nil
  }

  func renameMetadata(_ metadata: FileMetadata, to name: String) throws {
    fileNameToMetadata[name] = fileNameToMetadata[metadata.fileName]
    fileContents[name] = fileContents[metadata.fileName]
    fileNameToMetadata[metadata.fileName] = nil
    fileContents[metadata.fileName] = nil
  }
}
