// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/PropertyPathTokenTest.swift

import JSONPath
import Testing



@Suite("Sextant: PropertyPathToken")
struct PropertyPathTokenTestsPorted: SextantTestCase {
    let jsonSimpleMap = """
        {
            "foo": "foo-val",
            "bar": "bar-val",
            "baz": {
                "baz-child": "baz-child-val"
            }
        }
    """
    
    let jsonSimpleArray = """
        [
            {
                "foo": "foo-val-0",
                "bar": "bar-val-0",
                "baz": {
                    "baz-child": "baz-child-val"
                }
            },
            {
                "foo": "foo-val-1",
                "bar": "bar-val-1",
                "baz": {
                    "baz-child": "baz-child-val"
                }
            }
        ]
    """
    
    @Test func test_property_not_found() throws {
        expectCount(jsonSimpleMap, "$.not-found", 0)
    }

    @Test func test_property_not_found_deep() throws {
        expectCount(jsonSimpleMap, "$.foo.not-found", 0)
    }

    @Test func test_property_not_found_option_throw() throws {
        expectCount(jsonSimpleMap, "$.not-found", 0)
    }

    @Test func test_map_value_can_be_read_from_map() throws {
        expectValues(jsonSimpleMap, "$.foo", ["foo-val"])
    }

    @Test func test_map_value_can_be_read_from_array() throws {
        expectValues(jsonSimpleArray, "$[*].foo", ["foo-val-0", "foo-val-1"])
    }

    @Test func test_map_value_can_be_read_from_child_map() throws {
        expectValues(jsonSimpleMap, "$.baz.baz-child", ["baz-child-val"])
    }
}
