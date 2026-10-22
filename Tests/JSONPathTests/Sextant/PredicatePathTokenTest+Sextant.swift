// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/PredicatePathTokenTest.swift

import JSONPath
import Testing

@Suite("Sextant: PredicatePathToken")
struct PredicatePathTokenTestsPorted: SextantTestCase {
    let jsonArray2 = """
            [
                {
                    "foo": "foo-val-0",
                    "int": 0,
                    "decimal": 0.0
                },
                {
                    "foo": "foo-val-1",
                    "int": 1,
                    "decimal": 0.1
                },
                {
                    "foo": "foo-val-2",
                    "int": 2,
                    "decimal": 0.2
                },
                {
                    "foo": "foo-val-3",
                    "int": 3,
                    "decimal": 0.3
                },
                {
                    "foo": "foo-val-4",
                    "int": 4,
                    "decimal": 0.4
                },
                {
                    "foo": "foo-val-5",
                    "int": 5,
                    "decimal": 0.5
                },
                {
                    "foo": "foo-val-6",
                    "int": 6,
                    "decimal": 0.6
                },
                {
                    "foo": "foo-val-7",
                    "int": 7,
                    "decimal": 0.7,
                    "bool": true
                }
            ]
        """

    @Test func test_a_filter_predicate_can_be_evaluated_on_string_criteria() throws {
        expectValues(
            jsonArray2, "$[?(@.foo == 'foo-val-1')]",
            [
                [
                    "foo": "foo-val-1",
                    "int": 1,
                    "decimal": 0.1,
                ]
            ])
    }

    @Test func test_a_filter_predicate_can_be_evaluated_on_int_criteria() throws {
        expectValues(
            jsonArray2, "$[?(@.int == 1)]",
            [
                [
                    "foo": "foo-val-1",
                    "int": 1,
                    "decimal": 0.1,
                ]
            ])
    }

    @Test func test_a_filter_predicate_can_be_evaluated_on_decimal_criteria() throws {
        expectValues(
            jsonArray2, "$[?(@.int == 1)]",
            [
                [
                    "foo": "foo-val-1",
                    "int": 1,
                    "decimal": 0.1,
                ]
            ])
    }

    @Test func test_multiple_criteria_can_be_used() throws {
        expectValues(
            jsonArray2, "$[?(@.decimal == 0.1 && @.int == 1)]",
            [
                [
                    "foo": "foo-val-1",
                    "int": 1,
                    "decimal": 0.1,
                ]
            ])
    }

    @Test func test_field_existence_can_be_checked() throws {
        expectValues(
            jsonArray2, "$[?(@.bool)]",
            [
                [
                    "foo": "foo-val-7",
                    "int": 7,
                    "decimal": 0.7,
                    "bool": true,
                ]
            ])
    }

    @Test func test_boolean_criteria_evaluates() throws {
        expectValues(
            jsonArray2, "$[?(@.bool == true)]",
            [
                [
                    "foo": "foo-val-7",
                    "int": 7,
                    "decimal": 0.7,
                    "bool": true,
                ]
            ])
    }
}
