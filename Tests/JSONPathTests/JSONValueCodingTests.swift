import JSONPath
import Testing

@Suite("JSONValue Codable bridge")
struct JSONValueCodingTests {
    struct Book: Codable, Equatable {
        enum Kind: String, Codable { case reference, fiction }
        var title: String
        var kind: Kind
        var price: Double
        var pages: Int?
        var tags: [String]
        var ratings: [String: Int]
    }

    @Test func roundTripsCodableTypes() throws {
        let book = Book(title: "Moby Dick", kind: .fiction, price: 8.99, pages: nil, tags: ["sea"], ratings: ["a": 5])
        let value = try JSONValue(encoding: book)
        #expect(value == ["title": "Moby Dick", "kind": "fiction", "price": 8.99, "tags": ["sea"], "ratings": ["a": 5]])
        #expect(try value.decode(as: Book.self) == book)
    }

    @Test func decodesQueryResults() throws {
        let document = try JSONValue(parsing: #"{"books": [{"title": "A", "kind": "reference", "price": 1, "tags": [], "ratings": {}}, {"title": "B", "kind": "fiction", "price": 2.5, "pages": 300, "tags": ["x"], "ratings": {"z": 1}}]}"#)
        let books = try JSONValueDecoder().decode(Book.self, from: JSONPath("$.books[?@.price > 2]").values(in: document))
        #expect(books.map(\.title) == ["B"])
        #expect(books[0].pages == 300)
    }

    @Test func keyedContainersExposeKeysInDocumentOrder() throws {
        struct Keys: Decodable {
            let keys: [String]
            init(from decoder: any Decoder) throws {
                struct Key: CodingKey {
                    var stringValue: String
                    var intValue: Int? { nil }
                    init(stringValue: String) { self.stringValue = stringValue }
                    init?(intValue: Int) { nil }
                }
                keys = try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)
            }
        }
        let value = try JSONValue(parsing: #"{"z": 1, "a": 2, "m": 3}"#)
        #expect(try value.decode(as: Keys.self).keys == ["z", "a", "m"])
    }

    @Test func numbersAndErrors() throws {
        #expect(try JSONValue.integer(3).decode(as: Double.self) == 3)
        #expect(try JSONValue.number(4.0).decode(as: Int.self) == 4)
        #expect(throws: DecodingError.self) { try JSONValue.number(4.5).decode(as: Int.self) }
        #expect(throws: DecodingError.self) { try JSONValue.integer(300).decode(as: UInt8.self) }
        #expect(throws: DecodingError.self) { try JSONValue.string("x").decode(as: Int.self) }
        #expect(throws: DecodingError.self) { try JSONValue.object([:]).decode(as: [Int].self) }
        #expect(throws: EncodingError.self) { try JSONValue(encoding: Double.infinity) }
        #expect(try JSONValue(encoding: UInt64.max) == .number(Double(UInt64.max)))
        #expect(try JSONValue(encoding: Optional<Int>.none) == .null)
    }

    @Test func prettyPrinting() throws {
        let value: JSONValue = ["b": [1, ["c": true]], "a": [:], "e": []]
        #expect(value.jsonString(prettyPrinted: true) == "{\n  \"b\": [\n    1,\n    {\n      \"c\": true\n    }\n  ],\n  \"a\": {},\n  \"e\": []\n}")
        #expect(value.jsonString(prettyPrinted: false, sortedKeys: true) == #"{"a":{},"b":[1,{"c":true}],"e":[]}"#)
        #expect(try JSONValue(parsing: value.jsonString(prettyPrinted: true)) == value)
    }
}
