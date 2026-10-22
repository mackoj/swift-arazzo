// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ArrayIndexFilterTest.swift

import JSONPath
import Testing

@Suite("Sextant: ArrayIndexFilter")
struct ArrayIndexFilterTestPorted: SextantTestCase {
    let json = "[1, 3, 5, 7, 8, 13, 20]"

    @Test func test_tail_does_not_throw_when_index_out_of_bounds() throws {
        expectValues(json, "$[-10:]", [1, 3, 5, 7, 8, 13, 20])
    }

    @Test func test_head_does_not_throw_when_index_out_of_bounds() throws {
        expectValues(json, "$[:10]", [1, 3, 5, 7, 8, 13, 20])
    }

    @Test func test_head_grabs_correct() throws {
        expectValues(json, "$[:3]", [1, 3, 5])
    }

    @Test func test_tail_grabs_correct() throws {
        expectValues(json, "$[-3:]", [8, 13, 20])
    }

    @Test func test_head_tail_grabs_correct() throws {
        expectValues(json, "$[0:3]", [1, 3, 5])
    }

    @Test func test_can_access_items_from_end_with_negative_index() throws {
        expectValues(json, "$[-3]", [8])
    }
}
