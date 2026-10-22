// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/JsonPathTest.swift

import JSONPath
import Testing



@Suite("Sextant: JsonPath")
struct JsonPathTestPorted: SextantTestCase {
    let jsonArray = """
        [
            {
                "value": 1
            },
            {
                "value": 2
            },
            {
                "value": 3
            },
            {
                "value": 4
            }
        ]
    """
    
    let jsonDocument1 = """
        {
            "store": {
                "book": [
                    {
                        "category": "reference",
                        "author": "Nigel Rees",
                        "title": "Sayings of the Century",
                        "display-price": 8.95
                    },
                    {
                        "category": "fiction",
                        "author": "Evelyn Waugh",
                        "title": "Sword of Honour",
                        "display-price": 12.99
                    },
                    {
                        "category": "fiction",
                        "author": "Herman Melville",
                        "title": "Moby Dick",
                        "isbn": "0-553-21311-3",
                        "display-price": 8.99
                    },
                    {
                        "category": "fiction",
                        "author": "J. R. R. Tolkien",
                        "title": "The Lord of the Rings",
                        "isbn": "0-395-19395-8",
                        "display-price": 22.99
                    }
                ],
                "bicycle": {
                    "color": "red",
                    "display-price": 19.95,
                    "foo:bar": "fooBar",
                    "dot.notation": "new",
                    "dash-notation": "dashes"
                }
            }
        }
    """
    
    let jsonProduct = """
        {
            "product": [
                {
                    "version": "A",
                    "codename": "Seattle",
                    "attr.with.dot": "A"
                },
                {
                    "version": "4.0",
                    "codename": "Montreal",
                    "attr.with.dot": "B"
                }
            ]
        }
    """
    
    let jsonArrayExpand = """
        [
            {
                "parent": "ONE",
                "child": {
                    "name": "NAME_ONE"
                }
            },
            [
                {
                    "parent": "TWO",
                    "child": {
                        "name": "NAME_TWO"
                    }
                }
            ]
        ]
    """
    
    @Test func test_missing_prop() throws {
        expectValues(jsonDocument1, "$.store.book[*].fooBar.not", [])
    }
    
    @Test func test_bracket_notation_with_dots() throws {
        let json = """
            {
                "store": {
                    "book": [
                        {
                            "author.name": "Nigel Rees",
                            "category": "reference",
                            "price": 8.95,
                            "title": "Sayings of the Century"
                        }
                    ]
                }
            }
        """
        expectValues(json, "$.store.book[0]['author.name']", ["Nigel Rees"])
    }
    
    @Test func test_null_object_in_path() throws {
        let json = """
            {
                "success": true,
                "data": {
                    "user": 3,
                    "own": null,
                    "passes": null,
                    "completed": null
                },
                "data2": {
                    "user": 3,
                    "own": null,
                    "passes": [
                        {
                            "id": "1"
                        }
                    ],
                    "completed": null
                },
                "version": 1371160528774
            }
        """
        
        expectValues(json, "$.data.passes[0].id", [])
        expectValues(json, "$.data2.passes[0].id", ["1"])
    }
    
    @Test func test_array_start_expands() throws {
        expectValues(jsonArrayExpand, "$[?(@['parent'] == 'ONE')].child.name", ["NAME_ONE"])
    }
    
    @Test func test_bracket_notation_can_be_used_in_path() throws {
        expectValues(jsonDocument1, "$.['store'].bicycle.['dot.notation']", ["new"])
        
        expectValues(jsonDocument1, "$['store']['bicycle']['dot.notation']", ["new"])
        expectValues(jsonDocument1, "$.['store']['bicycle']['dot.notation']", ["new"])
        expectValues(jsonDocument1, "$.['store'].['bicycle'].['dot.notation']", ["new"])
        
        expectValues(jsonDocument1, "$.['store'].bicycle.['dash-notation']", ["dashes"])
        expectValues(jsonDocument1, "$['store']['bicycle']['dash-notation']", ["dashes"])
        expectValues(jsonDocument1, "$.['store']['bicycle']['dash-notation']", ["dashes"])
        expectValues(jsonDocument1, "$.['store'].['bicycle'].['dash-notation']", ["dashes"])

    }
    
    @Test func test_filter_an_array() throws {
        expectCount(jsonArray, "$.[?(@.value == 1)]", 1)
    }
    
    @Test func test_filter_an_array_on_index() throws {
        expectValues(jsonArray, "$.[1].value", [2])
    }
    
    @Test func test_read_path_with_colon() throws {
        expectValues(jsonDocument1, "$['store']['bicycle']['foo:bar']", ["fooBar"])
    }
    
    @Test func test_read_document_from_root() throws {
        expectCount(jsonDocument1, "$.store", 1)
    }
    
    @Test func test_read_store_book_1() throws {
        expectValues(jsonDocument1, "$.store.book[1]", [[
            "category": "fiction",
            "author": "Evelyn Waugh",
            "title": "Sword of Honour",
            "display-price": 12.99
        ]])
    }
    
    @Test func test_read_store_book_wildcard() throws {
        expectCount(jsonDocument1, "$.store.book[*]", 4)
    }
    
    @Test func test_read_store_book_author() throws {
        expectValues(jsonDocument1, "$.store.book[0,1].author", ["Nigel Rees", "Evelyn Waugh"])
        expectValues(jsonDocument1, "$.store.book[*].author", ["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
        expectValues(jsonDocument1, "$.['store'].['book'][*].['author']", ["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
        expectValues(jsonDocument1, "$['store']['book'][*]['author']", ["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
        expectValues(jsonDocument1, "$['store'].book[*]['author']", ["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
    }
    
    @Test func test_all_authors() throws {
        expectValues(jsonDocument1, "$..author", ["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
    }
    
    @Test func test_all_store_properties() throws {
        expectPaths(jsonDocument1, "$.store.*", [
            "$['store']['bicycle']",
            "$['store']['book']"
        ])
    }
    
    @Test func test_all_prices_in_store() throws {
        let values = try #require(sextantQuery(jsonDocument1, "$.store..['display-price']"))
        #expect(values.compactMap(\.doubleValue).sorted() == [8.95, 8.99, 12.99, 19.95, 22.99])
    }
    
    @Test func test_access_array_by_index_from_tail() throws {
        expectValues(jsonDocument1, "$..book[1:].author", ["Evelyn Waugh","Herman Melville","J. R. R. Tolkien"])
    }
    
    @Test func test_read_store_book_index_0_and_1() throws {
        expectValues(jsonDocument1, "$.store.book[0,1].author", ["Nigel Rees", "Evelyn Waugh"])
    }
    
    @Test func test_read_store_book_pull_first_2() throws {
        expectValues(jsonDocument1, "$.store.book[:2].author", ["Nigel Rees", "Evelyn Waugh"])
    }
    
    @Test func test_read_store_book_filter_by_isbn() throws {
        expectValues(jsonDocument1, "$.store.book[?(@.isbn)].isbn", ["0-553-21311-3", "0-395-19395-8"])
        expectCount(jsonDocument1, "$.store.book[?(@['isbn'])].isbn", 2)
    }
    
    @Test func test_all_books_cheaper_than_10() throws {
        expectValues(jsonDocument1, "$..book[?(@['display-price'] < 10)].title", ["Sayings of the Century", "Moby Dick"])
        expectValues(jsonDocument1, "$..book[?(@.display-price < 10)].title", ["Sayings of the Century", "Moby Dick"])
    }
    
    @Test func test_all_books() throws {
        expectCount(jsonDocument1, "$..book", 1)
    }
    
    @Test func test_dot_in_predicate_works() throws {
        expectValues(jsonProduct, "$.product[?(@.version=='4.0')].codename", ["Montreal"])
    }
    
    @Test func test_dots_in_predicate_works() throws {
        expectValues(jsonProduct, "$.product[?(@['attr.with.dot']=='A')].codename", ["Seattle"])
    }
    
    @Test func test_all_books_with_category_reference() throws {
        expectValues(jsonDocument1, "$..book[?(@.category=='reference')].title", ["Sayings of the Century"])
        expectValues(jsonDocument1, "$.store.book[?(@.category=='reference')].title", ["Sayings of the Century"])
    }
    
    @Test func test_all_members_of_all_documents() throws {
        expectCount(jsonDocument1, "$..*", 30)
    }
    
    @Test func test_access_index_out_of_bounds_does_not_throw_exception() throws {
        expectValues(jsonDocument1, "$.store.book[100].author", [])
    }
    
    @Test func test_exists_filter_with_nested_path() throws {
        expectCount(jsonDocument1, "$..[?(@.bicycle.color)]", 1)
        expectCount(jsonDocument1, "$..[?(@.bicycle.numberOfGears)]", 0)
    }
    
    @Test func test_prevent_stack_overflow_error_when_unclosed_property() throws {
        expectInvalid(jsonDocument1, "$['boo','foo][?(@ =~ /bar/)]")
    }
}
