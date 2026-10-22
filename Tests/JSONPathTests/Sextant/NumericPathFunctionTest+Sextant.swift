// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/NumericPathFunctionTest.swift

import JSONPath
import Testing



@Suite("Sextant: NumericPathFunction")
struct NumericPathFunctionTestPorted: SextantTestCase {
    
    @Test func testAverageOfDoubles() throws {
        expectValues(jsonNumberSeries, "$.numbers.avg()", [5.5])
    }
    
    @Test func testAverageOfEmptyListNegative() throws {
        expectInvalid(jsonNumberSeries, "$.empty.avg()")
    }
    
    @Test func testSumOfDouble() throws {
        expectValues(jsonNumberSeries, "$.numbers.sum()", [55])
    }
    
    @Test func testSumOfEmptyListNegative() throws {
        expectInvalid(jsonNumberSeries, "$.empty.sum()")
    }
    
    @Test func testMaxOfDouble() throws {
        expectValues(jsonNumberSeries, "$.numbers.max()", [10])
    }
    
    @Test func testMaxOfEmptyListNegative() throws {
        expectInvalid(jsonNumberSeries, "$.empty.max()")
    }
    
    @Test func testMinOfDouble() throws {
        expectValues(jsonNumberSeries, "$.numbers.min()", [1])
    }
    
    @Test func testMinOfEmptyListNegative() throws {
        expectInvalid(jsonNumberSeries, "$.empty.min()")
    }
    
    @Test func testStdDevOfDouble() throws {
        expectValues(jsonNumberSeries, "$.numbers.stddev()", [2.8722813232690143])
    }
    
    @Test func testStddevOfEmptyListNegative() throws {
        expectInvalid(jsonNumberSeries, "$.empty.stddev()")
    }
}
