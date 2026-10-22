// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ReturnTypeTests.swift

import JSONPath
import Testing



@Suite("Sextant: ReturnType")
struct ReturnTypeTestsPorted: SextantTestCase {
    // Adapted: Sextant decodes the document with JSONSerialization; we query the JSON text directly.
    var root: String { jsonDocument }
    
    @Test func test_assert_strings_can_be_read() throws {
        expectValues(root, "$.string-property", ["string-value"])
        expectPaths(root, "$.string-property", ["$['string-property']"])
    }
    
    @Test func test_assert_ints_can_be_read() throws {
        expectValues(root, "$.int-max-property", [.integer(SextantFixtures.uint32Max)])
        expectPaths(root, "$.int-max-property", ["$['int-max-property']"])
    }
    
    @Test func test_assert_longs_can_be_read() throws {
        expectValues(root, "$.long-max-property", [.number(SextantFixtures.sizeMax)])
        expectPaths(root, "$.long-max-property", ["$['long-max-property']"])
    }
    
    @Test func test_assert_boolean_values_can_be_read() throws {
        expectValues(root, "$.boolean-property", [true])
        expectPaths(root, "$.boolean-property", ["$['boolean-property']"])
    }
    
    @Test func test_assert_arrays_can_be_read() throws {
        #expect(sextantQuery(root, "$.store.book")?.first?.arrayValue?.count == 4)
        expectPaths(root, "$.store.book", ["$['store']['book']"])
    }
    
    @Test func test_assert_maps_can_be_read() throws {
        expectValues(root, "$.store.book[0]", [
            [
                "author": "Nigel Rees",
                "title": "Sayings of the Century",
                "display-price": 8.95,
                "category": "reference"
            ]
        ])
        expectPaths(root, "$.store.book[0]", ["$['store']['book'][0]"])
    }
    
    @Test func test_a_path_evaluation_can_be_returned_as_PATH_LIST() throws {
        expectPaths(root, "$..author", [
            "$['store']['book'][0]['author']",
            "$['store']['book'][1]['author']",
            "$['store']['book'][2]['author']",
            "$['store']['book'][3]['author']"
        ])
    }
}
