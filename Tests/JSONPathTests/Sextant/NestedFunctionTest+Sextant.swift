// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/NestedFunctionTest.swift

import JSONPath
import Testing

@Suite("Sextant: NestedFunction")
struct NestedFunctionTestPorted: SextantTestCase {

    @Test func testParameterAverageFunctionCall() throws {
        expectValues(jsonNumberSeries, "$.avg($.numbers.min(), $.numbers.max())", [5.5])
    }

    @Test func testArrayAverageFunctionCall() throws {
        expectValues(jsonNumberSeries, "$.numbers.avg()", [5.5])
    }

    @Test func testArrayAverageFunctionCallWithParameters() throws {
        expectValues(jsonNumberSeries, "$.numbers.sum($.numbers.min(), $.numbers.max())", [66.0])
    }

    @Test func testJsonInnerArgumentArray() throws {
        expectValues(jsonNumberSeries, "$.sum(5, 3, $.numbers.max(), 2)", [20.0])
    }

    @Test func testSimpleLiteralArgument() throws {
        expectValues(jsonNumberSeries, "$.sum(5)", [5.0])
        expectValues(jsonNumberSeries, "$.sum(50)", [50.0])
    }

    @Test func testStringConcat() throws {
        expectValues(jsonTextSeries, "$.text.concat()", ["abcdef"])
    }

    @Test func testStringConcatWithJSONParameter() throws {
        expectValues(jsonTextSeries, #"$.text.concat("-", "ghijk")"#, ["abcdef-ghijk"])
    }

    @Test func testStringConcatWithSubpaths() throws {
        expectValues(jsonTextSeries, #"$.concat($.nestedFields[0].name,$.nestedFields[0].index)"#, ["A0"])
    }

    @Test func testStringConcatIssue7() throws {
        let json1 = #"{"x":"1","Y":2}"#
        expectValues(json1, #"$.concat($.x,"-",$.Y)"#, ["1-2"])

        let json2 = #"{"x":"1","Y":5}"#
        expectValues(json2, #"$.concat($.x,"-",$.Y)"#, ["1-5"])

        let json3 = #"{"x":"1","Y":8}"#
        expectValues(json3, #"$.concat($.x,"-",$.Y)"#, ["1-8"])
    }

    @Test func testAppendNumber() throws {
        expectValues(jsonNumberSeries, "$.numbers.append(11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 0).avg()", [10.0])
    }

    @Test func testAppendTextAndNumberThenSum() throws {
        expectValues(jsonNumberSeries, #"$.numbers.append("0", "11").sum()"#, [55.0])
    }

    @Test func testErrantCloseBraceNegative() throws {
        expectInvalid(jsonNumberSeries, "$.numbers.append(0, 1, 2}).avg()")
    }

    @Test func testErrantCloseBracketNegative() throws {
        expectInvalid(jsonNumberSeries, "$.numbers.append(0, 1, 2]).avg()")
    }

    @Test func testUnclosedFunctionCallNegative() throws {
        expectInvalid(jsonNumberSeries, "$.numbers.append(0, 1, 2")
    }
}
