// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ArraySlicingTest.swift

import JSONPath
import Testing



@Suite("Sextant: ArraySlicing")
struct ArraySlicingTestPorted: SextantTestCase {
    let jsonArray = "[1, 3, 5, 7, 8, 13, 20]"
    
    @Test func test_get_by_position() throws {
        expectValues(jsonArray, "$[3]", [7])
    }
    
    @Test func test_get_from_index() throws {
        expectValues(jsonArray, "$[:3]", [ 1, 3, 5 ])
    }

    @Test func test_get_between_index() throws {
        expectValues(jsonArray, "$[1:5]", [ 3, 5, 7, 8 ])
    }

    @Test func test_get_between_index_2() throws {
        expectValues(jsonArray, "$[0:1]", [ 1 ])
    }

    @Test func test_get_between_index_3() throws {
        expectValues(jsonArray, "$[0:2]", [ 1, 3 ])
    }

    @Test func test_get_between_index_out_of_bounds() throws {
        expectValues(jsonArray, "$[1:15]", [ 3, 5, 7, 8, 13, 20 ])
    }

    @Test func test_get_from_tail_index() throws {
        expectValues(jsonArray, "$[-3:]", [ 8, 13, 20 ])
    }

    @Test func test_get_from_tail() throws {
        expectValues(jsonArray, "$[3:]", [ 7, 8, 13, 20 ])
    }

    @Test func test_get_indexes() throws {
        expectValues(jsonArray, "$[0,1,2]", [ 1, 3, 5 ])
    }
}
