// Harness for the tests ported from Sextant (https://github.com/KittyMac/Sextant),
// MIT License, Copyright (c) 2021 Rocco Bowling. The shared documents come from Sextant's TestsBase.

import JSONPath
import Testing

/// The documents Sextant's `TestsBase` makes available to every test.
protocol SextantTestCase {}

extension SextantTestCase {
    var jsonDocument: String { SextantFixtures.jsonDocument }
    var jsonNumberSeries: String { SextantFixtures.jsonNumberSeries }
    var jsonTextSeries: String { SextantFixtures.jsonTextSeries }
}

enum SextantFixtures {
    static let uint32Max = 4_294_967_295
    /// `SIZE_MAX` does not fit in `Int`; JSON parsing turns it into a `Double`.
    static let sizeMax = 18_446_744_073_709_551_615.0

    static let jsonDocument = """
        {
            "string-property": "string-value",
            "int-max-property": 4294967295,
            "long-max-property": 18446744073709551615,
            "boolean-property": true,
            "null-property": null,
            "int-small-property": 1,
            "max-price": 10,
            "store": {
                "book": [
                    {
                        "category": "reference",
                        "author": "Nigel Rees",
                        "title": "Sayings of the Century",
                        "display-price": 8.95
                    },
                    {
                        "category": "fiction",
                        "author": "Evelyn Waugh",
                        "title": "Sword of Honour",
                        "display-price": 12.99
                    },
                    {
                        "category": "fiction",
                        "author": "Herman Melville",
                        "title": "Moby Dick",
                        "isbn": "0-553-21311-3",
                        "display-price": 8.99
                    },
                    {
                        "category": "fiction",
                        "author": "J. R. R. Tolkien",
                        "title": "The Lord of the Rings",
                        "isbn": "0-395-19395-8",
                        "display-price": 22.99
                    }
                ],
                "bicycle": {
                    "foo": "baz",
                    "escape": "Esc\\b\\f\\n\\r\\t\\n\\t\\u002A",
                    "color": "red",
                    "display-price": 19.95,
                    "foo:bar": "fooBar",
                    "dot.notation": "new",
                    "dash-notation": "dashes"
                }
            },
            "foo": "bar",
            "@id": "ID"
        }
        """

    static let jsonNumberSeries = """
        {
            "empty": [],
            "numbers": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        }
        """

    static let jsonTextSeries = """
        {
            "urls": [
                "http://api.worldbank.org/countries/all/?format=json",
                "http://api.worldbank.org/countries/all/?format=json"
            ],
            "text": ["a", "b", "c", "d", "e", "f"],
            "nestedFields": [
                {"index": 0, "name": "A"},
                {"index": 1, "name": "B"},
                {"index": 2, "name": "C"}
            ]
        }
        """
}

// MARK: - Query helpers (Jayway dialect, like Sextant)

/// Runs a Jayway query; `nil` when the path is invalid or evaluation fails (Sextant returns `nil` then).
func sextantQuery(_ json: String, _ path: String) -> [JSONValue]? {
    OracleLog.record(json, path)
    guard let document = try? JSONValue(parsing: json) else {
        Issue.record("Fixture is not valid JSON: \(json.prefix(60))")
        return nil
    }
    return try? JSONPath(path, dialect: .jayway).values(in: document)
}

func sextantPaths(_ json: String, _ path: String) -> [String]? {
    guard let document = try? JSONValue(parsing: json) else { return nil }
    return (try? JSONPath(path, dialect: .jayway).paths(in: document))?.map(\.description)
}

/// Mirrors Sextant's `XCTAssertEqualAny`: string lists compare without order, other values
/// compare in order with JSON value semantics (`1 == 1.0`, member order ignored).
func expectValues(
    _ json: String, _ path: String, _ expected: [JSONValue], sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let actual = sextantQuery(json, path) else {
        Issue.record("Query \(path) failed", sourceLocation: sourceLocation)
        return
    }
    #expect(sextantEqual(actual, expected), "\(path) → \(actual), expected \(expected)", sourceLocation: sourceLocation)
}

func sextantEqual(_ actual: [JSONValue], _ expected: [JSONValue]) -> Bool {
    let actualStrings = actual.compactMap(\.stringValue)
    let expectedStrings = expected.compactMap(\.stringValue)
    if actualStrings.count == actual.count, expectedStrings.count == expected.count {
        return actualStrings.sorted() == expectedStrings.sorted()
    }
    return actual.count == expected.count && zip(actual, expected).allSatisfy { $0.isDeepEqual(to: $1) }
}

func expectCount(_ json: String, _ path: String, _ expected: Int?, sourceLocation: SourceLocation = #_sourceLocation) {
    let actual = sextantQuery(json, path)?.count
    #expect(actual == expected, "\(path) → \(actual.map(String.init) ?? "nil") results", sourceLocation: sourceLocation)
}

func expectPaths(
    _ json: String, _ path: String, _ expected: [String], sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let actual = sextantPaths(json, path) else {
        Issue.record("Query \(path) failed", sourceLocation: sourceLocation)
        return
    }
    #expect(actual.sorted() == expected.sorted(), "\(path) → \(actual)", sourceLocation: sourceLocation)
}

func expectInvalid(_ json: String, _ path: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let actual = sextantQuery(json, path)
    #expect(actual == nil, "\(path) should fail but returned \(actual ?? [])", sourceLocation: sourceLocation)
}

/// When `SEXTANT_ORACLE_LOG` is set, every evaluated (document, path) pair is appended to that file
/// (JSON lines) so the results can be compared with Sextant itself.
enum OracleLog {
    static func record(_ json: String, _ path: String) {
        guard let file = environment("SEXTANT_ORACLE_LOG") else { return }
        let line = JSONValue.object(["json": .string(json), "path": .string(path)]).jsonString + "\n"
        appendLine(line, to: file)
    }
}
