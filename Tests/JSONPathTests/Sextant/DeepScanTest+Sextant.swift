// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/DeepScanTest.swift

import JSONPath
import Testing

@Suite("Sextant: DeepScan")
struct DeepScanTestPorted: SextantTestCase {

    @Test func test_when_deep_scanning_non_array_subscription_is_ignored() throws {
        expectValues("{\"x\": [0,1,[0,1,2,3,null],null]}", "$..[2][3]", [3])
        expectValues("{\"x\": [0,1,[0,1,2,3,null],null], \"y\": [0,1,2]}", "$..[2][3]", [3])
        expectValues("{\"x\": [0,1,[0,1,2],null], \"y\": [0,1,2]}", "$..[2][3]", [])
    }

    @Test func test_when_deep_scanning_null_subscription_is_ignored() throws {
        expectValues("{\"x\": [null,null,[0,1,2,3,null],null]}", "$..[2][3]", [3])
        expectValues("{\"x\": [null,null,[0,1,2,3,null],null], \"y\": [0,1,null]}", "$..[2][3]", [3])
    }

    @Test func test_when_deep_scanning_array_index_oob_is_ignored() throws {
        expectValues("{\"x\": [0,1,[0,1,2,3,10],null]}", "$..[4]", [10])
        expectValues("{\"x\": [null,null,[0,1,2,3]], \"y\": [null,null,[0,1]]}", "$..[2][3]", [3])
    }

    @Test func test_definite_upstream_illegal_array_access_throws() throws {
        expectValues("{\"foo\": {\"bar\": null}}", "$.foo.bar.[5]", [])
        //expectValues("{\"foo\": {\"bar\": null}}", "$.foo.bar.[5, 10]", [])
        //expectValues("{\"foo\": {\"bar\": 4}}", "$.foo.bar.[5]", [])
        //expectValues("{\"foo\": {\"bar\": 4}}", "$.foo.bar.[5, 10]", [])
        //expectValues("{\"foo\": {\"bar\": []}}", "$.foo.bar.[5]", [])
    }

    @Test func test_when_deep_scanning_illegal_property_access_is_ignored() throws {
        expectCount("{\"x\": {\"foo\": {\"bar\": 4}}, \"y\": {\"foo\": 1}}", "$..foo", 2)
        expectValues("{\"x\": {\"foo\": {\"bar\": 4}}, \"y\": {\"foo\": 1}}", "$..foo.bar", [4])
        expectValues("{\"x\": {\"foo\": {\"bar\": 4}}, \"y\": {\"foo\": 1}}", "$..[*].foo.bar", [4])
        expectValues("{\"x\": {\"foo\": {\"baz\": 4}}, \"y\": {\"foo\": 1}}", "$..[*].foo.bar", [])
    }

    @Test func test_when_deep_scanning_illegal_predicate_is_ignored() throws {
        expectValues("{\"x\": {\"foo\": {\"bar\": 4}}, \"y\": {\"foo\": 1}}", "$..foo[?(@.bar)].bar", [4])
        expectValues("{\"x\": {\"foo\": {\"bar\": 4}}, \"y\": {\"foo\": 1}}", "$..[*]foo[?(@.bar)].bar", [4])
    }

    @Test func test_when_deep_scanning_require_properties_is_ignored_on_scan_target() throws {
        expectCount("[{\"x\": {\"foo\": {\"x\": 4}, \"x\": null}, \"y\": {\"x\": 1}}, {\"x\": []}]", "$..x", 5)
        expectValues("{\"foo\": {\"bar\": 4}}", "$..foo.bar", [4])
        expectValues("{\"foo\": {\"baz\": 4}}", "$..foo.bar", [])
    }

    @Test func test_when_deep_scanning_require_properties_is_ignored_on_scan_target_but_not_on_children() throws {
        expectValues("{\"foo\": {\"baz\": 4}}", "$..foo.bar", [])
    }

    @Test func test_when_deep_scanning_leaf_multi_props_work() throws {
        expectValues(
            #"[{"a": "a-val", "b": "b-val", "c": "c-val"}, [1, 5], {"a": "a-val"}]"#, "$..['a', 'c']",
            ["a-val", "c-val", "a-val"])
    }

    @Test func test_require_single_property_ok() throws {
        expectValues(#"[{"a":"a0"},{"a":"a1"}]"#, "$..a", ["a0", "a1"])
    }

    @Test func test_require_single_property() throws {
        expectValues(#"[{"a":"a0"},{"b":"b2"}]"#, "$..a", ["a0"])
    }

    @Test func test_require_multi_property_all_match() throws {
        let json = #"[{"a":"aa","b":"bb"},{"a":"aa","b":"bb"}]"#
        expectValues(json, "$..['a', 'b']", ["aa", "bb", "aa", "bb"])
    }

    @Test func test_require_multi_property_some_match() throws {
        let json = #"[{"a":"aa","b":"bb"},{"a":"aa","d":"dd"}]"#
        expectValues(json, "$..['a', 'b']", ["aa", "bb", "aa"])
    }

    @Test func test_scan_for_single_property() throws {
        let json = #"[{"a":"aa"},{"b":"bb"},{"b":{"b":"bb"},"ab":{"a":{"a":"aa"},"b":{"b":"bb"}}}]"#
        expectValues(json, "$..['a']", ["aa", ["a": "aa"], "aa"])
    }

    @Test func test_scan_for_property_path() throws {
        let json = #"[{"a":"aa"},{"x":"xx"},{"a":{"x":"xx"}},{"z":{"a":{"x":"xx"}}}]"#
        expectValues(json, "$..['a'].x", ["xx", "xx"])
    }

    @Test func test_scan_for_property_path_missing_required_property() throws {
        let json = #"[{"a":"aa"},{"x":"xx"},{"a":{"x":"xx"}},{"z":{"a":{"x":"xx"}}}]"#
        expectValues(json, "$..['a'].x", ["xx", "xx"])
    }

    @Test func test_scans_can_be_filtered() throws {
        let json =
            #"[{"color":{"val":"brown"},"mammal":true},{"color":{"val":"white"},"mammal":true},{"mammal":false}]"#
        expectValues(json, "$..[?(@.mammal == true)].color", [["val": "brown"], ["val": "white"]])
    }

    @Test func test_scan_with_a_function_filter() throws {
        expectCount(jsonDocument, "$..*[?(@.length() > 5)]", 19)
    }

    @Test func test_deepScanPathDefault() throws {
        let json = "{ \"index\": \"index\", \"data\": { \"array\": [ { \"object1\": { \"name\": \"robert\" } } ] } }"
        expectValues(json, "$..array[0]", [["object1": ["name": "robert"]]])
    }
}
