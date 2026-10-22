import JSONPath
import Testing

@Suite("JSON parser")
struct JSONParserTests {
    @Test func parsesAndPreservesOrder() throws {
        let value = try JSONValue(
            parsing: #"{"z": 1, "a": [true, false, null], "m": {"x": 1.5, "y": "line\n\u00e9\ud834\udd1e"}}"#)
        #expect(value.objectValue?.keys == ["z", "a", "m"])
        #expect(value["a"] == [true, false, nil])
        #expect(value["m"]?["x"] == .number(1.5))
        #expect(value["m"]?["y"] == "line\n\u{e9}\u{1D11E}")
        #expect(
            value.jsonString == "{\"z\":1,\"a\":[true,false,null],\"m\":{\"x\":1.5,\"y\":\"line\\n\u{e9}\u{1D11E}\"}}")
    }

    @Test func numbers() throws {
        #expect(try JSONValue(parsing: "0") == 0)
        #expect(try JSONValue(parsing: "-12") == -12)
        #expect(try JSONValue(parsing: "1e3") == .number(1000))
        #expect(try JSONValue(parsing: "9223372036854775807") == .integer(Int.max))
        #expect(try JSONValue(parsing: "18446744073709551615") == .number(18_446_744_073_709_551_615.0))
    }

    @Test(arguments: [
        "", "01", "1.", ".5", "+1", "[1,]", "{\"a\":1,}", "'a'", "\"\u{01}\"", "\"\\x\"", "\"\\ud800\"", "nul", "[1] 2",
        "{\"a\" 1}",
    ])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: JSONValue.ParseError.self) { try JSONValue(parsing: text) }
    }

    @Test func duplicateKeysKeepLastValue() throws {
        #expect(try JSONValue(parsing: #"{"a": 1, "b": 2, "a": 3}"#).jsonString == #"{"a":3,"b":2}"#)
    }
}

@Suite("JSONPath API")
struct JSONPathAPITests {
    static let store = try! JSONValue(
        parsing: """
            {"store": {"book": [
              {"category": "reference", "author": "Nigel Rees", "price": 8.95},
              {"category": "fiction", "author": "Evelyn Waugh", "price": 12.99},
              {"category": "fiction", "author": "Herman Melville", "isbn": "0-553-21311-3", "price": 8.99}
            ], "bicycle": {"color": "red", "price": 19.95}}}
            """)

    @Test func nodesValuesAndPaths() throws {
        let path = try JSONPath("$.store.book[?@.price < 10].author")
        #expect(try path.values(in: Self.store) == ["Nigel Rees", "Herman Melville"])
        #expect(
            try path.paths(in: Self.store).map(\.description) == [
                "$['store']['book'][0]['author']", "$['store']['book'][2]['author']",
            ])
        #expect(try path.paths(in: Self.store).first?.jsonPointer.description == "/store/book/0/author")
        #expect(try path.matches(Self.store))
        #expect(try JSONPath("$.nope").firstValue(in: Self.store) == nil)
        #expect(try Self.store.query("$..price").count == 4)
    }

    @Test func dialectDifferences() throws {
        let object: JSONValue = ["a": 1, "b": ["a": 2]]
        // A filter on an object: RFC 9535 tests the members, Jayway tests the object itself.
        #expect(try JSONPath("$[?@.a]").values(in: object) == [["a": 2]])
        #expect(try JSONPath("$[?(@.a)]", dialect: .jayway).values(in: object) == [object])
        // Loose vs strict comparisons.
        let list: JSONValue = [["v": "1"], ["v": 1]]
        #expect(try JSONPath("$[?@.v == 1]").values(in: list).count == 1)
        #expect(try JSONPath("$[?(@.v == 1)]", dialect: .jayway).values(in: list).count == 2)
        // Slice step 0.
        #expect(try JSONPath("$[::0]").values(in: [1, 2]) == [])
        #expect(try JSONPath("$[::0]", dialect: .jayway).values(in: [1, 2]) == [1, 2])
        // Jayway-only syntax.
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("$.numbers.length()") }
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("store.book") }
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("$[?(@.a in [1,2])]") }
        #expect(try JSONPath("store.book[0].author", dialect: .jayway).values(in: Self.store) == ["Nigel Rees"])
    }

    @Test func rfcFunctionsWorkInBothDialects() throws {
        let doc: JSONValue = ["pets": [["name": "Rex"], ["name": "Tom"]]]
        // Jayway applies the filter to the root object itself – the Arazzo spec's
        // `$[?count(@.pets) > 0]` example relies on this.
        #expect(try JSONPath("$[?count(@.pets[*]) > 1]", dialect: .jayway).values(in: doc).count == 1)
        #expect(try JSONPath("$.pets[?match(@.name, 'R.*')].name").values(in: doc) == ["Rex"])
        #expect(try JSONPath("$.pets[?search(@.name, 'o')].name", dialect: .jayway).values(in: doc) == ["Tom"])
        #expect(try JSONPath("$[?length(@) == 2]").values(in: doc).count == 1)
    }

    @Test func descriptions() throws {
        #expect(
            try JSONPath("$.store.book[0,1]['author', \"price\"]").description
                == "$['store']['book'][0, 1]['author', 'price']")
        #expect(
            try JSONPath("$..book[?@.price<10 && (@.isbn || !@.author)]").description
                == "$..['book'][?@['price'] < 10 && (@['isbn'] || !@['author'])]")
        #expect(try JSONPath("$.a.b", dialect: .jayway).description == "$['a']['b']")
        #expect(try JSONPath("$.a").isSingular)
        #expect(try !JSONPath("$.a[*]").isSingular)
    }

    @Test func parseErrorsCarryPositions() {
        do {
            _ = try JSONPath("$.store[?@.price <]")
            Issue.record("expected an error")
        } catch let error as JSONPath.ParseError {
            #expect(error.position > 0)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(JSONPath.validate("$.ok") == nil)
        #expect(JSONPath.validate("$.") != nil)
    }

    @Test func functionErrorsAreEvaluationErrors() {
        #expect(throws: JSONPath.EvaluationError.self) {
            try JSONPath("$.empty.avg()", dialect: .jayway).values(in: ["empty": []])
        }
    }

    @Test func pathsAreSendableAndHashable() throws {
        let a = try JSONPath("$.a")
        let b = try JSONPath("$['a']")
        #expect(a == b)  // same query, different spelling
        #expect(Set([a, b]).count == 1)
    }
}

@Suite("Mutations")
struct MutationTests {
    @Test func setAtPointer() throws {
        var value: JSONValue = ["items": [1, 2], "meta": [:]]
        try value.set(3, at: JSONPointer("/items/-"))
        try value.set(0, at: JSONPointer("/items/0"))
        try value.set("x", at: JSONPointer("/meta/name"))
        try value.set(9, at: JSONPointer("/items/3"))
        #expect(value == ["items": [0, 2, 3, 9], "meta": ["name": "x"]])
        #expect(throws: JSONValue.MutationError.self) { try value.set(1, at: JSONPointer("/missing/deep")) }
        #expect(throws: JSONValue.MutationError.self) { try value.set(1, at: JSONPointer("/items/10")) }
        try value.set("root", at: JSONPointer.root)
        #expect(value == "root")
    }

    @Test func removeKeepsIndicesConsistent() throws {
        var value: JSONValue = [0, 1, 2, 3, 4, 5]
        let removed = try value.remove(JSONPath("$[?@ < 3]"))
        #expect(removed == 3)
        #expect(value == [3, 4, 5])
    }

    @Test func normalizedPathSubscriptAndOrdering() throws {
        let value: JSONValue = ["a": [["b": 1]]]
        let path: NormalizedPath = ["a", 0, "b"]
        #expect(value[path] == 1)
        #expect(path.description == "$['a'][0]['b']")
        #expect(NormalizedPath(["a", 1]) > NormalizedPath(["a", 0]))
        #expect(NormalizedPath(["it's"]).description == #"$['it\'s']"#)
    }
}
