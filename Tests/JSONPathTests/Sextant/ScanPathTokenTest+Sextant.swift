// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/ScanPathTokenTest.swift

import JSONPath
import Testing

@Suite("Sextant: ScanPathToken")
struct ScanPathTokenTestsPorted: SextantTestCase {
    let jsonDocument1 = """
        {
            "store": {
                "book": [
                    {
                        "category": "reference",
                        "author": "Nigel Rees",
                        "title": "Sayings of the Century",
                        "price": 8.95,
                        "address": {
                            "street": "fleet street",
                            "city": "London"
                        }
                    },
                    {
                        "category": "fiction",
                        "author": "Evelyn Waugh",
                        "title": "Sword of Honour",
                        "price": 12.9,
                        "address": {
                            "street": "Baker street",
                            "city": "London"
                        }
                    },
                    {
                        "category": "fiction",
                        "author": "J. R. R. Tolkien",
                        "title": "The Lord of the Rings",
                        "isbn": "0-395-19395-8",
                        "price": 22.99,
                        "address": {
                            "street": "Svea gatan",
                            "city": "Stockholm"
                        }
                    }
                ],
                "bicycle": {
                    "color": "red",
                    "price": 19.95,
                    "address": {
                        "street": "Söder gatan",
                        "city": "Stockholm"
                    },
                    "items": [
                        [
                            "A",
                            "B",
                            "C"
                        ],
                        1,
                        2,
                        3,
                        4,
                        5
                    ]
                }
            }
        }
        """

    let jsonDocument2 = """
           {
               "firstName": "John",
               "lastName": "doe",
               "age": 26,
               "address": {
                   "streetAddress": "naist street",
                   "city": "Nara",
                   "postalCode": "630-0192"
               },
               "phoneNumbers": [
                   {
                       "type": "iPhone",
                       "number": "0123-4567-8888"
                   },
                   {
                       "type": "home",
                       "number": "0123-4567-8910"
                   }
               ]
           }
        """

    @Test func test_a_document_can_be_scanned_for_property() throws {
        expectValues(
            jsonDocument1, "$..author",
            [
                "Nigel Rees", "Evelyn Waugh", "J. R. R. Tolkien",
            ])
        expectPaths(
            jsonDocument1, "$..author",
            [
                #"$['store']['book'][0]['author']"#,
                #"$['store']['book'][1]['author']"#,
                #"$['store']['book'][2]['author']"#,
            ])
    }

    @Test func test_a_document_can_be_scanned_for_property_path() throws {
        expectValues(
            jsonDocument1, "$..address.street",
            [
                "Söder gatan", "fleet street", "Baker street", "Svea gatan",
            ])
        expectPaths(
            jsonDocument1, "$..address.street",
            [
                #"$['store']['bicycle']['address']['street']"#,
                #"$['store']['book'][0]['address']['street']"#,
                #"$['store']['book'][1]['address']['street']"#,
                #"$['store']['book'][2]['address']['street']"#,
            ])
    }

    @Test func test_a_document_can_be_scanned_for_wildcard() throws {
        //print(jsonDocument1.query(paths: "$..[*]"))
        expectPaths(
            jsonDocument1, "$..[*]",
            [
                "$['store']",
                "$['store']['bicycle']",
                "$['store']['book']",
                "$['store']['bicycle']['address']",
                "$['store']['bicycle']['color']",
                "$['store']['bicycle']['price']",
                "$['store']['bicycle']['items']",
                "$['store']['bicycle']['address']['city']",
                "$['store']['bicycle']['address']['street']",
                "$['store']['bicycle']['items'][0]",
                "$['store']['bicycle']['items'][1]",
                "$['store']['bicycle']['items'][2]",
                "$['store']['bicycle']['items'][3]",
                "$['store']['bicycle']['items'][4]",
                "$['store']['bicycle']['items'][5]",
                "$['store']['bicycle']['items'][0][0]",
                "$['store']['bicycle']['items'][0][1]",
                "$['store']['bicycle']['items'][0][2]",
                "$['store']['book'][0]",
                "$['store']['book'][1]",
                "$['store']['book'][2]",
                "$['store']['book'][0]['address']",
                "$['store']['book'][0]['author']",
                "$['store']['book'][0]['price']",
                "$['store']['book'][0]['category']",
                "$['store']['book'][0]['title']",
                "$['store']['book'][0]['address']['city']",
                "$['store']['book'][0]['address']['street']",
                "$['store']['book'][1]['address']",
                "$['store']['book'][1]['author']",
                "$['store']['book'][1]['price']",
                "$['store']['book'][1]['category']",
                "$['store']['book'][1]['title']",
                "$['store']['book'][1]['address']['city']",
                "$['store']['book'][1]['address']['street']",
                "$['store']['book'][2]['address']",
                "$['store']['book'][2]['author']",
                "$['store']['book'][2]['price']",
                "$['store']['book'][2]['isbn']",
                "$['store']['book'][2]['category']",
                "$['store']['book'][2]['title']",
                "$['store']['book'][2]['address']['city']",
                "$['store']['book'][2]['address']['street']",
            ])
    }

    @Test func test_a_document_can_be_scanned_for_wildcard2() throws {
        expectPaths(
            jsonDocument1, "$.store.book[0]..*",
            [
                "$['store']['book'][0]['address']",
                "$['store']['book'][0]['author']",
                "$['store']['book'][0]['price']",
                "$['store']['book'][0]['category']",
                "$['store']['book'][0]['title']",
                "$['store']['book'][0]['address']['city']",
                "$['store']['book'][0]['address']['street']",
            ])
    }

    @Test func test_a_document_can_be_scanned_for_wildcard3() throws {
        expectPaths(
            jsonDocument2, "$.phoneNumbers[0]..*",
            [
                "$['phoneNumbers'][0]['number']",
                "$['phoneNumbers'][0]['type']",
            ])
    }

    @Test func test_a_document_can_be_scanned_for_predicate_match() throws {
        expectPaths(
            jsonDocument1, "$..[?(@.address.city == 'Stockholm')]",
            [
                "$['store']['bicycle']",
                "$['store']['book'][2]",
            ])
    }

    @Test func test_a_document_can_be_scanned_for_existence() throws {
        expectPaths(
            jsonDocument1, "$..[?(@.isbn)]",
            [
                "$['store']['book'][2]"
            ])
    }

}
