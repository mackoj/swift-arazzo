// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ArrayPathTokenTest.swift

import JSONPath
import Testing



@Suite("Sextant: ArrayPathToken")
struct ArrayPathTokenTestPorted: SextantTestCase {
    let json = #"[{"foo":"foo-val-0"},{"foo":"foo-val-1"},{"foo":"foo-val-2"},{"foo":"foo-val-3"},{"foo":"foo-val-4"},{"foo":"foo-val-5"},{"foo":"foo-val-6"}]"#
    
    @Test func test_array_can_select_multiple_indexes() throws {
        expectValues(json, "$[0,1]", [
            [ "foo" : "foo-val-0" ], ["foo" : "foo-val-1" ]
        ])
    }
    
    @Test func test_array_can_be_sliced_to_2() throws {
        expectValues(json, "$[:2]", [
            [ "foo" : "foo-val-0" ], ["foo" : "foo-val-1" ]
        ])
    }
    
    @Test func test_array_can_be_sliced_to_2_from_tail() throws {
        expectValues(json, "$[:-5]", [
            [ "foo" : "foo-val-0" ], ["foo" : "foo-val-1" ]
        ])
    }
    
    @Test func test_array_can_be_sliced_from_2() throws {
        expectValues(json, "$[5:]", [
            [ "foo" : "foo-val-5" ], ["foo" : "foo-val-6" ]
        ])
    }
    
    @Test func test_array_can_be_sliced_from_2_from_tail() throws {
        expectValues(json, "$[-2:]", [
            [ "foo" : "foo-val-5" ], ["foo" : "foo-val-6" ]
        ])
    }
    
    @Test func test_array_can_be_sliced_between() throws {
        expectValues(json, "$[2:4]", [
            [ "foo" : "foo-val-2" ], ["foo" : "foo-val-3" ]
        ])
    }
    
}
