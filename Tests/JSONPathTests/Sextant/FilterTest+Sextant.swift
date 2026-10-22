// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/FilterTest.swift

import JSONPath
import Testing

@Suite("Sextant: Filter")
struct FilterTestPorted: SextantTestCase {
    let jsonObject = """
            {
                "int-key": 1,
                "long-key": 3000000000,
                "double-key": 10.1,
                "boolean-key": true,
                "null-key": null,
                "string-key": "string",
                "string-key-empty": "",
                "char-key": "c",
                "arr-empty": [

                ],
                "int-arr": [
                    0,
                    1,
                    2,
                    3,
                    4
                ],
                "string-arr": [
                    "a",
                    "b",
                    "c",
                    "d",
                    "e"
                ]
            }
        """

    // MARK - SMJFilterTest - EQ

    @Test func test_int_eq_evals() throws {
        expectCount(jsonObject, "[?(@.int-key == 1)]", 1)
        expectCount(jsonObject, "[?(@.int-key == 666)]", 0)
    }

    @Test func test_int_eq_string_evals() throws {
        expectCount(jsonObject, "[?(@.int-key == '1')]", 1)
        expectCount(jsonObject, "[?(@.int-key == '666')]", 0)

        expectCount(jsonObject, "[?(1 == '1')]", 1)
        expectCount(jsonObject, "[?('1' == 1)]", 1)

        expectCount(jsonObject, "[?(1 === '1')]", 0)
        expectCount(jsonObject, "[?('1' === 1)]", 0)

        expectCount(jsonObject, "[?(1 === 1)]", 1)
    }

    @Test func test_long_eq_evals() throws {
        expectCount(jsonObject, "[?(@.long-key == 3000000000)]", 1)
        expectCount(jsonObject, "[?(@.long-key == 666)]", 0)
    }

    @Test func test_double_eq_evals() throws {
        expectCount(jsonObject, "[?(@.double-key == 10.1)]", 1)
        expectCount(jsonObject, "[?(@.double-key == 10.10)]", 1)
        expectCount(jsonObject, "[?(@.double-key == 10.11)]", 0)
    }

    @Test func test_string_eq_evals() throws {
        expectCount(jsonObject, "[?(@.string-key == 'string')]", 1)
        expectCount(jsonObject, "[?(@.string-key == '666')]", 0)
    }

    @Test func test_boolean_eq_evals() throws {
        expectCount(jsonObject, "[?(@.boolean-key == true)]", 1)
        expectCount(jsonObject, "[?(@.boolean-key == false)]", 0)
    }

    @Test func test_null_eq_evals() throws {
        expectCount(jsonObject, "[?(@.null-key == null)]", 1)
        expectCount(jsonObject, "[?(@.null-key == '666')]", 0)
        expectCount(jsonObject, "[?(@.string-key == null)]", 0)
    }

    @Test func test_arr_eq_evals() throws {
        expectCount(jsonObject, "[?(@.arr-empty == [])]", 1)
        expectCount(jsonObject, "[?(@.int-arr == [0,1,2,3,4])]", 1)
        expectCount(jsonObject, "[?(@.int-arr == [0,1,2,3])]", 0)
        expectCount(jsonObject, "[?(@.int-arr == [0,1,2,3,4,5])]", 0)
    }

    // MARK - SMJFilterTest - NE

    @Test func test_int_ne_evals() throws {
        expectCount(jsonObject, "[?(@.int-key != 1)]", 0)
        expectCount(jsonObject, "[?(@.int-key != 666)]", 1)
    }

    @Test func test_long_ne_evals() throws {
        expectCount(jsonObject, "[?(@.long-key != 3000000000)]", 0)
        expectCount(jsonObject, "[?(@.long-key != 666)]", 1)
    }

    @Test func test_double_ne_evals() throws {
        expectCount(jsonObject, "[?(@.double-key != 10.1)]", 0)
        expectCount(jsonObject, "[?(@.double-key != 10.10)]", 0)
        expectCount(jsonObject, "[?(@.double-key != 10.11)]", 1)
    }

    @Test func test_string_ne_evals() throws {
        expectCount(jsonObject, "[?(@.string-key != 'string')]", 0)
        expectCount(jsonObject, "[?(@.string-key != '666')]", 1)
    }

    @Test func test_boolean_ne_evals() throws {
        expectCount(jsonObject, "[?(@.boolean-key != true)]", 0)
        expectCount(jsonObject, "[?(@.boolean-key != false)]", 1)
    }

    @Test func test_null_ne_evals() throws {
        expectCount(jsonObject, "[?(@.null-key != null)]", 0)
        expectCount(jsonObject, "[?(@.null-key != '666')]", 1)
        expectCount(jsonObject, "[?(@.string-key != null)]", 1)
    }

    // MARK - SMJFilterTest - LT

    @Test func test_int_lt_evals() throws {
        expectCount(jsonObject, "[?(@.int-key < 10)]", 1)
        expectCount(jsonObject, "[?(@.int-key < 0)]", 0)
    }

    @Test func test_long_lt_evals() throws {
        expectCount(jsonObject, "[?(@.long-key < 4000000000)]", 1)
        expectCount(jsonObject, "[?(@.long-key < 666)]", 0)
    }

    @Test func test_double_lt_evals() throws {
        expectCount(jsonObject, "[?(@.double-key < 100.1)]", 1)
        expectCount(jsonObject, "[?(@.double-key < 1.1)]", 0)
    }

    @Test func test_string_lt_evals() throws {
        expectCount(jsonObject, "[?(@.char-key < 'x')]", 1)
        expectCount(jsonObject, "[?(@.char-key < 'a')]", 0)
    }

    // MARK - SMJFilterTest - LTE

    @Test func test_int_lte_evals() throws {
        expectCount(jsonObject, "[?(@.int-key <= 10)]", 1)
        expectCount(jsonObject, "[?(@.int-key <= 1)]", 1)
        expectCount(jsonObject, "[?(@.int-key <= 0)]", 0)
    }

    @Test func test_long_lte_evals() throws {
        expectCount(jsonObject, "[?(@.long-key <= 4000000000)]", 1)
        expectCount(jsonObject, "[?(@.long-key <= 3000000000)]", 1)
        expectCount(jsonObject, "[?(@.long-key <= 666)]", 0)
    }

    @Test func test_double_lte_evals() throws {
        expectCount(jsonObject, "[?(@.double-key <= 100.1)]", 1)
        expectCount(jsonObject, "[?(@.double-key <= 10.1)]", 1)
        expectCount(jsonObject, "[?(@.double-key <= 1.1)]", 0)
    }

    // MARK - SMJFilterTest - GT

    @Test func test_int_gt_evals() throws {
        expectCount(jsonObject, "[?(@.int-key > 10)]", 0)
        expectCount(jsonObject, "[?(@.int-key > 0)]", 1)
    }

    @Test func test_long_gt_evals() throws {
        expectCount(jsonObject, "[?(@.long-key > 4000000000)]", 0)
        expectCount(jsonObject, "[?(@.long-key > 666)]", 1)
    }

    @Test func test_double_gt_evals() throws {
        expectCount(jsonObject, "[?(@.double-key > 100.1)]", 0)
        expectCount(jsonObject, "[?(@.double-key > 1.1)]", 1)
    }

    @Test func test_string_gt_evals() throws {
        expectCount(jsonObject, "[?(@.char-key > 'x')]", 0)
        expectCount(jsonObject, "[?(@.char-key > 'a')]", 1)
    }

    // MARK - SMJFilterTest - GTE

    @Test func test_int_gte_evals() throws {
        expectCount(jsonObject, "[?(@.int-key >= 10)]", 0)
        expectCount(jsonObject, "[?(@.int-key >= 1)]", 1)
        expectCount(jsonObject, "[?(@.int-key >= 0)]", 1)
    }

    @Test func test_long_gte_evals() throws {
        expectCount(jsonObject, "[?(@.long-key >= 4000000000)]", 0)
        expectCount(jsonObject, "[?(@.long-key >= 3000000000)]", 1)
        expectCount(jsonObject, "[?(@.long-key >= 666)]", 1)
    }

    @Test func test_double_gte_evals() throws {
        expectCount(jsonObject, "[?(@.double-key >= 100.1)]", 0)
        expectCount(jsonObject, "[?(@.double-key >= 10.1)]", 1)
        expectCount(jsonObject, "[?(@.double-key >= 1.1)]", 1)
    }

    // MARK - SMJFilterTest - Regex

    @Test func test_string_regex_evals() throws {
        expectCount(jsonObject, "[?(@.string-key =~ /^string$/)]", 1)
        expectCount(jsonObject, "[?(@.string-key =~ /^tring$/)]", 0)
        expectCount(jsonObject, "[?(@.null-key =~ /^string$/)]", 0)
        expectCount(jsonObject, "[?(@.int-key =~ /^string$/)]", 0)
    }

    // MARK - SMJFilterTest - JSON equality

    @Test func test_json_evals() throws {
        let json = "{\"foo\": [1,2], \"bar\": {\"a\":true}}"
        expectCount(json, "[?(@.foo == [1,2])]", 1)
    }

    // MARK - SMJFilterTest - IN

    @Test func test_string_in_evals_child_node_no_field() throws {
        let json = "{\"foo\": [\"false\",\"true\"], \"bar\": {\"a\":\"true\"}}"
        expectCount(json, "$..[?(@ contains 'ru')]", 2)
        expectCount(json, "$.foo.[?(@ contains 'ru')]", 1)
        expectCount(json, "$.bar.[?(@ contains 'ru')]", 0)
    }

    @Test func test_string_in_evals() throws {
        //expectCount(jsonObject, "[?(@.string-key IN [\"a\", null, \"string\"])]", 1)
        //expectCount(jsonObject, "[?(@.string-key IN [\"a\", null])]", 0)
        expectCount(jsonObject, "[?(@.null-key IN [\"a\", null])]", 1)
        //expectCount(jsonObject, "[?(@.null-key IN [\"a\", \"b\"])]", 0)
        //expectCount(jsonObject, "[?(@.string-arr IN [\"a\"])]", 0)
    }

    // MARK - SMJFilterTest - NIN

    @Test func test_string_nin_evals() throws {
        expectCount(jsonObject, "[?(@.string-key NIN [\"a\", null, \"string\"])]", 0)
        expectCount(jsonObject, "[?(@.string-key NIN [\"a\", null])]", 1)
        expectCount(jsonObject, "[?(@.null-key NIN [\"a\", null])]", 0)
        expectCount(jsonObject, "[?(@.null-key NIN [\"a\", \"b\"])]", 1)
        expectCount(jsonObject, "[?(@.string-arr NIN [\"a\"])]", 1)
    }

    // MARK - SMJFilterTest - ALL

    @Test func test_int_all_evals() throws {
        expectCount(jsonObject, "[?(@.int-arr ALL [0, 1])]", 1)
        expectCount(jsonObject, "[?(@.int-arr ALL [0, 7])]", 0)
    }

    @Test func test_string_all_evals() throws {
        expectCount(jsonObject, "[?(@.string-arr ALL [\"a\",\"b\"])]", 1)
        expectCount(jsonObject, "[?(@.string-arr ALL [\"a\",\"x\"])]", 0)
    }

    @Test func test_not_array_all_evals() throws {
        expectCount(jsonObject, "[?(@.string-key ALL [\"a\",\"b\"])]", 0)
    }

    // MARK - SMJFilterTest - SIZE

    @Test func test_array_size_evals() throws {
        expectCount(jsonObject, "[?(@.string-arr SIZE 5)]", 1)
        expectCount(jsonObject, "[?(@.string-arr SIZE 7)]", 0)
    }

    @Test func test_string_size_evals() throws {
        expectCount(jsonObject, "[?(@.string-key SIZE 6)]", 1)
        expectCount(jsonObject, "[?(@.string-key SIZE 7)]", 0)
    }

    @Test func test_other_size_evals() throws {
        expectCount(jsonObject, "[?(@.int-key SIZE 6)]", 0)
    }

    @Test func test_null_size_evals() throws {
        expectCount(jsonObject, "[?(@.null-key SIZE 6)]", 0)
    }

    // MARK - SMJFilterTest - SUBSETOF

    @Test func test_array_subsetof_evals() throws {
        expectCount(jsonObject, #"[?(@.string-arr SUBSETOF [ "a", "b", "c", "d", "e", "f", "g" ])]"#, 1)
        expectCount(jsonObject, #"[?(@.string-arr SUBSETOF [ "e", "d", "b", "c", "a" ])]"#, 1)
        expectCount(jsonObject, #"[?(@.string-arr SUBSETOF [ "a", "b", "c", "d" ])]"#, 0)
    }

    // MARK - SMJFilterTest - ANYOF

    @Test func test_array_anyof_evals() throws {
        expectCount(jsonObject, "[?(@.string-arr ANYOF [ \"a\", \"z\" ])]", 1)
        expectCount(jsonObject, "[?(@.string-arr ANYOF [ \"z\", \"b\", \"a\" ])]", 1)
        expectCount(jsonObject, "[?(@.string-arr ANYOF [ \"x\", \"y\", \"z\" ])]", 0)
    }

    // MARK - SMJFilterTest - NONEOF

    @Test func test_array_noneof_evals() throws {
        expectCount(jsonObject, "[?(@.string-arr NONEOF [ \"a\", \"z\" ])]", 0)
        expectCount(jsonObject, "[?(@.string-arr NONEOF [ \"z\", \"b\", \"a\" ])]", 0)
        expectCount(jsonObject, "[?(@.string-arr NONEOF [ \"x\", \"y\", \"z\" ])]", 1)
    }

    // MARK - SMJFilterTest - EXISTS

    @Test func test_exists_evals() throws {
        // SourceMac-Note: we support the "EXISTS" token, event if it's similar (and so redoundant) to don't use operator and right value.

        expectCount(jsonObject, "[?(@.string-key EXISTS true)]", 1)
        expectCount(jsonObject, "[?(@.string-key EXISTS false)]", 0)

        expectCount(jsonObject, "[?(@.missing-key EXISTS true)]", 0)
        expectCount(jsonObject, "[?(@.missing-key EXISTS false)]", 1)
    }

    // MARK - SMJFilterTest - TYPE

    @Test func test_type_evals() throws {
        //expectCount(jsonObject, "[?(@.string-key TYPE 'string')]", 1)
        expectCount(jsonObject, "[?(@.string-key TYPE 'number')]", 0)

        expectCount(jsonObject, "[?(@.int-key TYPE 'string')]", 0)
        expectCount(jsonObject, "[?(@.int-key TYPE 'number')]", 1)

        expectCount(jsonObject, "[?(@.int-arr TYPE 'json')]", 1)

        expectCount(jsonObject, "[?(@.string-key TYPE @.string-key)]", 1)
        expectCount(jsonObject, "[?(@.string-key TYPE @.int-key)]", 0)
    }

    // MARK - SMJFilterTest - EMPTY

    @Test func test_empty_evals() throws {
        expectCount(jsonObject, "[?(@.string-key EMPTY false)]", 1)
        expectCount(jsonObject, "[?(@.string-key EMPTY true)]", 0)

        expectCount(jsonObject, "[?(@.string-key-empty EMPTY true)]", 1)
        expectCount(jsonObject, "[?(@.string-key-empty EMPTY false)]", 0)

        expectCount(jsonObject, "[?(@.int-arr EMPTY false)]", 1)
        expectCount(jsonObject, "[?(@.int-arr EMPTY true)]", 0)

        expectCount(jsonObject, "[?(@.arr-empty EMPTY true)]", 1)
        expectCount(jsonObject, "[?(@.arr-empty EMPTY false)]", 0)

        expectCount(jsonObject, "[?(@.null-key EMPTY true)]", 0)
        expectCount(jsonObject, "[?(@.null-key EMPTY false)]", 0)
    }

    // MARK - SMJFilterTest - OR

    @Test func test_or_and_filters_evaluates() throws {
        let json = """
                {
                    "foo": true,
                    "bar": false
                }
            """
        expectCount(json, "[?(@.foo == true || @.bar == true)]", 1)
        expectCount(json, "[?(@.foo == true && @.bar == true)]", 0)
    }

    @Test func testFilterWithOrShortCircuit1() throws {
        let json = "{\"firstname\":\"Bob\",\"surname\":\"Smith\",\"age\":30}"
        expectCount(json, "[?((@.firstname == 'Bob' || @.firstname == 'Jane') && @.surname == 'Doe')]", 0)
    }

    @Test func testFilterWithOrShortCircuit2() throws {
        let json = "{\"firstname\":\"Bob\",\"surname\":\"Smith\",\"age\":30}"
        expectCount(json, "[?((@.firstname == 'Bob' || @.firstname == 'Jane') && @.surname == 'Smith')]", 1)
    }

    // MARK - SMJFilterTest - Others

    @Test func test_inline_in_criteria_evaluates() throws {
        expectCount(jsonDocument, #"$.store.book[?(@.category in ["reference", "fiction"])]"#, 4)
    }
}
