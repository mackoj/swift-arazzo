// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/MultiPropTest.swift

import JSONPath
import Testing



@Suite("Sextant: MultiProp")
struct MultiPropTestPorted: SextantTestCase {
    
    @Test func test_multi_prop_can_be_read_from_root() throws {
        let model = """
            {
                "a": "a-val",
                "b": "b-val",
                "c": "c-val"
            }
        """
        
        expectValues(model, "$['a', 'b']", ["a-val", "b-val"])
        expectValues(model, "$['a', 'd']", ["a-val"])
    }
    
    @Test func test_multi_props_can_be_non_leafs() throws {
        let json = """
            {
                "a": {
                    "v": 5
                },
                "b": {
                    "v": 4
                },
                "c": {
                    "v": 1
                }
            }
        """
        
        expectValues(json, "$['a', 'c'].v", [5, 1])
    }

    @Test func test_nonexistent_non_leaf_multi_props_ignored() throws {
        let json = """
            {
                "a": {
                    "v": 5
                },
                "b": {
                    "v": 4
                },
                "c": {
                    "v": 1
                }
            }
        """
        expectValues(json, "$['d', 'a', 'c', 'm'].v", [5, 1])
    }

    @Test func test_multi_props_with_post_filter() throws {
        let json = """
            {
                "a": {
                    "v": 5
                },
                "b": {
                    "v": 4
                },
                "c": {
                    "v": 1,
                    "flag": true
                }
            }
        """
        expectValues(json, "$['a', 'c'][?(@.flag)].v", [1])
    }

    @Test func test_deep_scan_does_not_affect_non_leaf_multi_props() throws {
        let json = """
            {
                "a": {
                    "v": 5
                },
                "b": {
                    "v": 4
                },
                "c": {
                    "v": 1,
                    "flag": true
                }
            }
        """
        expectValues(json, "$..['a', 'c'].v", [5, 1])
        expectValues(json, "$..['a', 'c'][?(@.flag)].v", [1])
    }

    @Test func test_multi_props_can_be_in_the_middle() throws {
        let json = """
            {
                "x": [
                    null,
                    {
                        "a": {
                            "v": 5
                        },
                        "b": {
                            "v": 4
                        },
                        "c": {
                            "v": 1
                        }
                    }
                ]
            }
        """
        
        expectValues(json, "$.x[1]['a', 'c'].v", [5, 1])
        expectValues(json, "$.x[*]['a', 'c'].v", [5, 1])
        expectValues(json, "$[*][*]['a', 'c'].v", [5, 1])
        expectValues(json, "$.x[1]['d', 'a', 'c', 'm'].v", [5, 1])
        expectValues(json, "$.x[*]['d', 'a', 'c', 'm'].v", [5, 1])
    }
    
}
