// Copyright © 2018 Brian's Brain. All rights reserved.

// swiftlint:disable force_cast

import CocoaLumberjack
import Foundation
import IGListKit

public struct FileMetadata: Equatable {
  public init(metadataItem: NSMetadataItem) {
    self.fileURL = metadataItem.value(forAttribute: NSMetadataItemURLKey) as! URL
    self.displayName = String(
      metadataItem.value(forAttribute: NSMetadataItemDisplayNameKey) as! NSString
    )
    self.contentType = String(
      metadataItem.value(forAttribute: NSMetadataItemContentTypeKey) as! NSString
    )
    self.downloadingStatus = String(metadataItem.value(
      forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
      ) as! NSString)
    self.isDownloading = (metadataItem.value(
      forAttribute: NSMetadataUbiquitousItemIsDownloadingKey
      ) as! NSNumber).boolValue
    self.isUploading = (metadataItem.value(
      forAttribute: NSMetadataUbiquitousItemIsUploadingKey
      ) as! NSNumber).boolValue
    let nsStringArray = metadataItem.value(
      forAttribute: NSMetadataItemContentTypeTreeKey
      ) as! [NSString]
    self.contentTypeTree = nsStringArray.map { String($0) }
  }

  public let fileURL: URL
  public let displayName: String
  public let contentType: String
  public let downloadingStatus: String
  public let isDownloading: Bool
  public let isUploading: Bool
  public let contentTypeTree: [String]
}

// Immutable value object with key properties of an NSMetadataItem, which apparently mutates.
public final class FileMetadataWrapper: Equatable {
  public init(metadataItem: NSMetadataItem) {
    self.value = FileMetadata(metadataItem: metadataItem)
  }

  public let value: FileMetadata

  public static func == (lhs: FileMetadataWrapper, rhs: FileMetadataWrapper) -> Bool {
    return lhs.value == rhs.value
  }

  public func downloadIfNeeded() {
    if value.downloadingStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
      FileMetadataWrapper.downloadItem(self)
    }
  }
}

extension FileMetadataWrapper: ListDiffable {
  public func diffIdentifier() -> NSObjectProtocol {
    return value.fileURL as NSURL
  }

  public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
    guard let otherItem = object as? FileMetadataWrapper else { return false }
    return value == otherItem.value
  }
}

extension FileMetadataWrapper {
  private static let downloadQueue = DispatchQueue(
    label: "org.brians-brain.FileMetadata.download",
    qos: .default,
    attributes: []
  )

  private static func downloadItem(_ item: FileMetadataWrapper) {
    downloadQueue.async {
      DDLogDebug("Downloading " + String(describing: item.value.fileURL))
      try? FileManager.default.startDownloadingUbiquitousItem(at: item.value.fileURL)
    }
  }
}