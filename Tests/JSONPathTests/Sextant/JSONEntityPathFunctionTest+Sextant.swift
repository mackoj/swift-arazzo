// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/JSONEntityPathFunctionTest.swift

import JSONPath
import Testing

@Suite("Sextant: JSONEntityPathFunction")
struct JSONEntityPathFunctionTestPorted: SextantTestCase {
    let jsonBatch = """
            {
                "batches": {
                    "minBatchSize": 10,
                    "results": [
                        {
                            "productId": 23,
                            "values": [
                                2,
                                45,
                                34,
                                23,
                                3,
                                5,
                                4,
                                3,
                                2,
                                1
                            ]
                        },
                        {
                            "productId": 23,
                            "values": [
                                52,
                                3,
                                12,
                                11,
                                18,
                                22,
                                1
                            ]
                        }
                    ]
                }
            }
        """

    @Test func testLengthOfTextArray() throws {
        expectValues(jsonTextSeries, "$['text'].length()", [6])
        expectValues(jsonTextSeries, "$['text'].size()", [6])
    }

    @Test func testLengthOfNumberArray() throws {
        expectValues(jsonNumberSeries, "$.numbers.length()", [10])
        expectValues(jsonNumberSeries, "$.numbers.size()", [10])
    }

    @Test func testLengthOfStructure() throws {
        expectValues(jsonBatch, "$.batches.length()", [2])
    }

    /**
     * The fictitious use-case/story - is we have a collection of batches with values indicating some quality metric.
     * We want to determine the average of the values for only the batch's values where the number of items in the batch
     * is greater than the min batch size which is encoded in the JSON document.
     *
     * We use the length function in the predicate to determine the number of values in each batch and then for those
     * batches where the count is greater than min we calculate the average batch value.
     *
     * Its completely contrived example, however, this test exercises functions within predicates.
     */
    @Test func testPredicateWithFunctionCallSingleMatch() throws {
        let path = "$.batches.results[?(@.values.length() >= $.batches.minBatchSize)].values.avg()"
        expectValues(jsonBatch, path, [12.2])
    }

    @Test func testPredicateWithFunctionCallTwoMatches() throws {
        let path = "$.batches.results[?(@.values.length() >= 3)].values.avg()";
        expectValues(jsonBatch, path, [12.2, 17])
    }
}
