// Copyright (c) 2018-2021  Brian Dewey. Covered by the Apache 2.0 license.

// swiftlint:disable identifier_name

import Combine
import Foundation
import Logging
import UniformTypeIdentifiers

struct LibraryThingBook: Codable {
  var title: String
  var authors: [LibraryThingAuthor]
  var date: Int?
  var review: String?
  var rating: Int?
  var isbn: [String: String]?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.title = try container.decode(String.self, forKey: .title)
    // LibraryThing encodes "no authors" as "an array with an empty array", not "an empty array"
    self.authors = (try? container.decode([LibraryThingAuthor].self, forKey: .authors)) ?? []
    self.date = Int(try container.decode(String.self, forKey: .date))
    self.review = try? container.decode(String.self, forKey: .review)
    self.rating = try? container.decode(Int.self, forKey: .rating)
    self.isbn = try? container.decode([String: String].self, forKey: .isbn)
  }
}

struct LibraryThingAuthor: Codable {
  var lf: String
  var fl: String
}

struct TypedData {
  var data: Data
  var type: UTType

  let uuid = UUID().uuidString
  var key: String {
    "./\(uuid).\(type.preferredFilenameExtension ?? "")"
  }
}

extension Book {
  init(_ libraryThingBook: LibraryThingBook) {
    self.title = libraryThingBook.title
    self.authors = libraryThingBook.authors.map { $0.fl }
    self.yearPublished = libraryThingBook.date
    self.isbn = libraryThingBook.isbn?["0"]
    self.isbn13 = libraryThingBook.isbn?["2"]
    self.review = libraryThingBook.review
    self.rating = libraryThingBook.rating
  }
}

enum OpenLibrary {
  static func coverImagePublisher(isbn: String) -> AnyPublisher<TypedData, Error> {
    let url = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg")!
    return URLSession.shared.dataTaskPublisher(for: url)
      .tryMap { data, response in
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
          throw URLError(.badServerResponse)
        }
        if let mimeType = httpResponse.mimeType, let type = UTType(mimeType: mimeType) {
          return TypedData(data: data, type: type)
        }
        if let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.8) {
          return TypedData(data: jpegData, type: .jpeg)
        }
        throw URLError(.cannotDecodeRawData)
      }
      .eraseToAnyPublisher()
  }
}