// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/NullHandlingTest.swift

import JSONPath
import Testing



@Suite("Sextant: NullHandling")
struct NullHandlingTestPorted: SextantTestCase {
    let jsonDocumentNull = """
        {
            "root-property": "root-property-value",
            "root-property-null": null,
            "children": [
                {
                    "id": 0,
                    "name": "name-0",
                    "age": 0
                },
                {
                    "id": 1,
                    "name": "name-1",
                    "age": null
                },
                {
                    "id": 3,
                    "name": "name-3"
                }
            ]
        }
    """
    
    @Test func test_not_defined_property_throws_PathNotFoundException() throws {
        expectValues(jsonDocumentNull, "$.children[0].child.age", [])
    }
    
    @Test func test_last_token_defaults_to_null() throws {
        expectValues(jsonDocumentNull, "$.children[2].age", [])
    }
    
    @Test func test_null_property_returns_null() throws {
        expectValues(jsonDocumentNull, "$.children[0].age", [0])
        expectValues(jsonDocumentNull, "$.children[1].age", [nil])
        expectValues(jsonDocumentNull, "$.children[2].age", [])
    }
    
    @Test func test_the_age_of_all_with_age_defined() throws {
        expectValues(jsonDocumentNull, "$.children[*].age", [0, nil])
    }
}
