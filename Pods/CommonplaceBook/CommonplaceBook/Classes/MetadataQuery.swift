// Copyright © 2018 Brian's Brain. All rights reserved.

import Foundation

public protocol MetadataQueryDelegate: class {
  func metadataQuery(_ metadataQuery: MetadataQuery, didFindItems items: [NSMetadataItem])
}

public final class MetadataQuery {
  
  private let query: NSMetadataQuery
  private weak var delegate: MetadataQueryDelegate?
  
    public init(predicate: NSPredicate?, delegate: MetadataQueryDelegate) {
    self.delegate = delegate
    query = NSMetadataQuery()
    query.predicate = predicate
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didFinishGatheringNotification(_:)),
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
      object: query
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didUpdateNotification(_:)),
      name: NSNotification.Name.NSMetadataQueryDidUpdate,
      object: query
    )
    query.enableUpdates()
    query.start()
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
  
  @objc func didFinishGatheringNotification(_ notification: NSNotification) {
    let items = query.results as! [NSMetadataItem]
    delegate?.metadataQuery(self, didFindItems: items)
  }
  
  @objc func didUpdateNotification(_ notification: NSNotification) {
    print("Received notification: \(notification.userInfo)")
    let items = query.results as! [NSMetadataItem]
    delegate?.metadataQuery(self, didFindItems: items)
  }
}
