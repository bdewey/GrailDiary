// Copyright (c) 2018-2021  Brian Dewey. Covered by the Apache 2.0 license.

import Foundation
import Logging
import UniformTypeIdentifiers

/// A protocol that the text views use to store images on paste
public protocol ImageStorage {
  /// Store image data.
  /// - parameter imageData: The image data to store
  /// - parameter suffix: Image data suffix that identifies the data format (e.g., "jpeg", "png")
  /// - returns: A string key that can locate this image later.
  func storeImageData(_ imageData: Data, type: UTType) throws -> String

  /// Given the key returned from `markdownEditingTextView(_:store:suffix:)`, retrieve the corresponding image data.
  func retrieveImageDataForKey(_ key: String) throws -> Data
}

extension ImageStorage {
  /// A replacement function that will replace an `.image` node with a text attachment containing the image (200px max dimension)
  func imageReplacement(
    node: SyntaxTreeNode,
    startIndex: Int,
    buffer: SafeUnicodeBuffer,
    attributes: inout AttributedStringAttributesDescriptor
  ) -> [unichar]? {
    let anchoredNode = AnchoredNode(node: node, startIndex: startIndex)
    guard let targetNode = anchoredNode.first(where: { $0.type == .linkTarget }) else {
      attributes.color = .quaternaryLabel
      return nil
    }
    let targetChars = buffer[targetNode.range]
    let target = String(utf16CodeUnits: targetChars, count: targetChars.count)
    do {
      let imageData = try retrieveImageDataForKey(target)
      // TODO: What's the right image width?
      if let image = imageData.image(maxSize: 200) {
        let attachment = NSTextAttachment()
        attachment.image = image
        attributes.attachment = attachment
        return Array("\u{fffc}".utf16) // "object replacement character"
      }
    } catch {
      Logger.shared.error("Unexpected error getting image data: \(error)")
    }

    // fallback -- show the markdown code instead of the image
    attributes.color = .quaternaryLabel
    return nil
  }
}

public struct BoundNote {
  let identifier: Note.Identifier
  let database: NoteDatabase
}

extension BoundNote: ImageStorage {
  public func storeImageData(_ imageData: Data, type: UTType) throws -> String {
    return try database.writeAssociatedData(imageData, noteIdentifier: identifier, role: "embeddedImage", type: type)
  }

  public func retrieveImageDataForKey(_ key: String) throws -> Data {
    return try database.readAssociatedData(from: identifier, key: key)
  }
}

public extension ParsedAttributedString.Settings {
  func renderingImages(from imageStorage: ImageStorage) -> Self {
    var copy = self
    copy.fullFormatFunctions[.image] = imageStorage.imageReplacement
    return copy
  }
}

public extension NoteDatabase {
  // TODO: Remove AssetRecord from the schema
  /// Stores arbitrary data in the database.
  /// - Parameters:
  ///   - data: The asset data to store
  ///   - key: A unique key for the data
  /// - Throws: .databaseIsNotOpen
  /// - Returns: The key??
  @available(*, deprecated, message: "Use writeAssociatedData: instead")
  func storeAssetData(_ data: Data, key: String) throws -> String {
    guard let dbQueue = dbQueue else {
      throw Error.databaseIsNotOpen
    }
    return try dbQueue.write { db in
      let asset = AssetRecord(id: key, data: data)
      try asset.save(db)
      return key
    }
  }

  /// Gets arbitrary data back from
  /// - Parameter key: Key for the asset data to retrieve.
  /// - Throws: .databaseIsNotOpen, .noSuchAsset
  /// - Returns: The data corresponding with `key`
  func retrieveAssetDataForKey(_ key: String) throws -> Data {
    guard let dbQueue = dbQueue else {
      throw Error.databaseIsNotOpen
    }
    guard let record = try dbQueue.read({ db in
      try AssetRecord.filter(key: key).fetchOne(db)
    }) else {
      throw Error.noSuchAsset
    }
    return record.data
  }

  func writeAssociatedData(_ data: Data, noteIdentifier: Note.Identifier, role: String, type: UTType) throws -> String {
    guard let dbQueue = dbQueue else {
      throw Error.databaseIsNotOpen
    }
    let key = ["./" + data.sha1Digest(), type.preferredFilenameExtension].compactMap { $0 }.joined(separator: ".")
    let binaryRecord = BinaryContentRecord(
      blob: data,
      noteId: noteIdentifier,
      key: key,
      role: role,
      mimeType: type.preferredMIMEType ?? "application/octet-stream"
    )
    try dbQueue.write { db in
      try binaryRecord.save(db)
    }
    return key
  }

  func readAssociatedData(from noteIdentifier: Note.Identifier, key: String) throws -> Data {
    guard let dbQueue = dbQueue else {
      throw Error.databaseIsNotOpen
    }
    return try dbQueue.read { db in
      guard let record = try BinaryContentRecord.fetchOne(
        db,
        key: [BinaryContentRecord.Columns.noteId.rawValue: noteIdentifier, BinaryContentRecord.Columns.key.rawValue: key]
      ) else {
        throw Error.noSuchAsset
      }
      return record.blob
    }
  }
}

// extension NoteDatabase: ImageStorage {
//  public func storeImageData(_ imageData: Data, suffix: String) throws -> String {
//    let key = imageData.sha1Digest() + "." + suffix
//    return try storeAssetData(imageData, key: key)
//  }
//
//  public func retrieveImageDataForKey(_ key: String) throws -> Data {
//    return try retrieveAssetDataForKey(key)
//  }
// }
