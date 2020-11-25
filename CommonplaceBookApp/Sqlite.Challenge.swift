//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

import Foundation
import GRDB

extension Sqlite {
  struct Challenge: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var index: Int
    var reviewCount: Int = 0
    var lapseCount: Int = 0
    var totalCorrect: Int = 0
    var totalIncorrect: Int = 0
    var lastReview: Date?
    var idealInterval: Double?
    var due: Date?
    var challengeTemplateId: Int64
    var spacedRepetitionFactor: Double = 2.5
    var modifiedDevice: Int64
    var timestamp: Date
    var updateSequenceNumber: Int64

    mutating func didInsert(with rowID: Int64, for column: String?) {
      id = rowID
    }

    enum Columns {
      static let index = Column(Challenge.CodingKeys.index)
      static let challengeTemplateId = Column(Challenge.CodingKeys.challengeTemplateId)
      static let due = Column(Challenge.CodingKeys.due)
      static let modifiedDevice = Column(Challenge.CodingKeys.modifiedDevice)
      static let timestamp = Column(Challenge.CodingKeys.timestamp)
      static let updateSequenceNumber = Column(Challenge.CodingKeys.updateSequenceNumber)
    }

    static let challengeTemplate = belongsTo(ChallengeTemplate.self)

    static let device = belongsTo(Device.self)

    var challengeTemplate: QueryInterfaceRequest<ChallengeTemplate> {
      request(for: Self.challengeTemplate)
    }

    static func createV1Table(in database: Database) throws {
      try database.create(table: "challenge", body: { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("index", .integer).notNull()
        table.column("reviewCount", .integer).notNull().defaults(to: 0)
        table.column("totalCorrect", .integer).notNull().defaults(to: 0)
        table.column("totalIncorrect", .integer).notNull().defaults(to: 0)
        table.column("lastReview", .datetime)
        table.column("due", .datetime)
        table.column("spacedRepetitionFactor", .double).notNull().defaults(to: 2.5)
        table.column("lapseCount", .double).notNull().defaults(to: 0)
        table.column("idealInterval", .double)
        table.column("challengeTemplateId", .integer)
          .notNull()
          .indexed()
          .references("challengeTemplate", onDelete: .cascade)
        table.column("modifiedDevice", .integer)
          .notNull()
          .indexed()
          .references("device", onDelete: .cascade)
        table.column("timestamp", .datetime)
          .notNull()
        table.column("updateSequenceNumber", .integer).notNull()
      })
      try database.create(index: "byChallengeTemplateIndex", on: "challenge", columns: ["index", "challengeTemplateId"], unique: true)
    }
  }
}

extension Sqlite.Challenge {
  enum MergeError: Swift.Error {
    case cannotLoadChallenge
  }

  /// Knows how to merge challenges between databases.
  struct MergeInfo: MergeInfoRecord, Decodable {
    // MARK: - Stored properties

    var id: Int64
    var index: Int64
    var challengeTemplateId: Int64
    var timestamp: Date
    var device: Sqlite.Device
    var updateSequenceNumber: Int64

    // MARK: - Computed properties

    static var cursorRequest: QueryInterfaceRequest<Self> {
      Sqlite.Challenge
        .including(required: Sqlite.Challenge.device)
        .asRequest(of: Sqlite.Challenge.MergeInfo.self)
    }

    var instanceRequest: QueryInterfaceRequest<Self> {
      Sqlite.Challenge
        .including(required: Sqlite.Challenge.device)
        .filter(key: ["index": index, "challengeTemplateId": challengeTemplateId])
        .asRequest(of: Sqlite.Challenge.MergeInfo.self)
    }

    var deviceUUID: String { device.uuid }

    func copy(from sourceDatabase: Database, to destinationDatabase: Database) throws {
      guard var originRecord = try Sqlite.Challenge
        .filter(key: ["index": index, "challengeTemplateId": challengeTemplateId])
        .fetchOne(sourceDatabase)
      else {
        throw MergeError.cannotLoadChallenge
      }
      if let destinationDevice = try Sqlite.Device.filter(Sqlite.Device.Columns.uuid == device.uuid).fetchOne(destinationDatabase) {
        originRecord.modifiedDevice = destinationDevice.id!
      } else {
        var deviceRecord = device
        deviceRecord.id = nil
        deviceRecord.updateSequenceNumber = updateSequenceNumber
        try deviceRecord.insert(destinationDatabase)
        originRecord.modifiedDevice = deviceRecord.id!
      }
      if let destinationRecord = try Sqlite.Challenge.filter(key: ["index": index, "challengeTemplateId": challengeTemplateId]).fetchOne(destinationDatabase) {
        originRecord.id = destinationRecord.id
        try originRecord.update(destinationDatabase)
      } else {
        originRecord.id = nil
        try originRecord.insert(destinationDatabase)
      }
    }
  }
}
