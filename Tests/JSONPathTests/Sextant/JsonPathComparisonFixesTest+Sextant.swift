// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/JsonPathComparisonFixesTest.swift

import JSONPath
import Testing

@Suite("Sextant: JsonPathComparisonFixes")
struct JsonPathComparisonFixesTestPorted: SextantTestCase {
    // fixes: https://github.com/javerous/SMJJSONPath/issues/6

    @Test func test_case1() throws {
        let json = #"{":": 42, "more": "string", "a": 1, "b": 2, "c": 3}"#
        expectValues(json, "$[1:3]", [])
    }

    @Test func test_case2() throws {
        let json = #"["first", "second"]"#
        expectValues(json, "$[:]", ["first", "second"])
    }

    @Test func test_case3() throws {
        let json = #"["first", "second"]"#
        expectValues(json, "$[::]", ["first", "second"])
    }

    @Test func test_case4() throws {
        let json = #"["first", "second", "third", "forth", "fifth"]"#
        expectValues(json, "$[0:3:2]", ["first", "third"])
    }

    @Test func test_case5() throws {
        let json = #"{",": "value", "another": "entry"}"#
        expectValues(json, "$[',']", ["value"])
    }

}
