// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Sextant's tests derive from Jayway JsonPath (Apache-2.0) via SMJJSONPath.
// Source: Tests/SextantTests/Jayway/InlineFilterTest.swift

import JSONPath
import Testing

@Suite("Sextant: InlineFilter")
struct InlineFilterTestPorted: SextantTestCase {

    @Test func test_root_context_can_be_referred_in_predicate() throws {
        expectValues(jsonDocument, "store.book[?(@.display-price <= $.max-price)].display-price", [8.95, 8.99])
    }

    @Test func test_multiple_context_object_can_be_refered() throws {
        expectCount(jsonDocument, "store.book[ ?(@.category == @.category) ]", 4)

        expectCount(jsonDocument, "store.book[ ?(@.category == @['category']) ]", 4)

        expectCount(jsonDocument, "store.book[ ?(@ == @) ]", 4)

        expectCount(jsonDocument, "store.book[ ?(@.category != @.category) ]", 0)

        expectCount(jsonDocument, "store.book[ ?(@.category != @) ]", 4)
    }

    @Test func test_simple_inline_or_statement_evaluates() throws {
        expectValues(
            jsonDocument, "store.book[ ?(@.author == 'Nigel Rees' || @.author == 'Evelyn Waugh') ].author",
            ["Nigel Rees", "Evelyn Waugh"])

        expectValues(
            jsonDocument,
            "store.book[ ?((@.author == 'Nigel Rees' || @.author == 'Evelyn Waugh') && @.display-price < 15) ].author",
            ["Nigel Rees", "Evelyn Waugh"])

        expectValues(
            jsonDocument,
            "store.book[ ?((@.author == 'Nigel Rees' || @.author == 'Evelyn Waugh') && @.category == 'reference') ].author",
            ["Nigel Rees"])

        expectValues(
            jsonDocument,
            "store.book[ ?((@.author == 'Nigel Rees') || (@.author == 'Evelyn Waugh' && @.category != 'fiction')) ].author",
            ["Nigel Rees"])
    }

    @Test func test_no_path_ref_in_filter_hit_all() throws {
        expectValues(
            jsonDocument, "$.store.book[?('a' == 'a')].author",
            ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"])
    }

    @Test func test_no_path_ref_in_filter_hit_none() throws {
        expectValues(jsonDocument, "$.store.book[?('a' == 'b')].author", [])
    }

    @Test func test_path_can_be_on_either_side_of_operator() throws {
        expectValues(jsonDocument, "$.store.book[?(@.category == 'reference')].author", ["Nigel Rees"])
        expectValues(jsonDocument, "$.store.book[?('reference' == @.category)].author", ["Nigel Rees"])
    }

    @Test func test_path_can_be_on_both_side_of_operator() throws {
        expectValues(
            jsonDocument, "$.store.book[?(@.category == @.category)].author",
            ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"])
    }

    @Test func test_patterns_can_be_evaluated() throws {
        expectValues(jsonDocument, "$.store.book[?(@.category =~ /reference/)].author", ["Nigel Rees"])
        expectValues(jsonDocument, "$.store.book[?(/reference/ =~ @.category)].author", ["Nigel Rees"])
    }

    @Test func test_patterns_can_be_evaluated_with_ignore_case() throws {
        expectValues(jsonDocument, "$.store.book[?(@.category =~ /REFERENCE/)].author", [])
        expectValues(jsonDocument, "$.store.book[?(@.category =~ /REFERENCE/i)].author", ["Nigel Rees"])
    }

    @Test func test_negate_exists_check() throws {
        expectValues(jsonDocument, "$.store.book[?(@.isbn)].author", ["Herman Melville", "J. R. R. Tolkien"])
        expectValues(jsonDocument, "$.store.book[?(!@.isbn)].author", ["Nigel Rees", "Evelyn Waugh"])
    }

    @Test func test_negate_exists_check_primitive() throws {
        let json = "[0,1,null,2,3]"
        expectValues(json, "$[?(@)]", [0, 1, nil, 2, 3])
        expectValues(json, "$[?(@ != null)]", [0, 1, 2, 3])
        expectValues(json, "$[?(!@)]", [])
    }

    @Test func test_equality_check_does_not_break_evaluation() throws {
        expectCount(#"[{"value":"5"}]"#, "$[?(@.value=='5')]", 1)
        expectCount(#"[{"value":5}]"#, "$[?(@.value==5)]", 1)

        expectCount(#"[{"value":"5.1.26"}]"#, "$[?(@.value=='5.1.26')]", 1)

        expectCount(#"[{"value":"5"}]"#, "$[?(@.value=='5.1.26')]", 0)
        expectCount(#"[{"value":5}]"#, "$[?(@.value=='5.1.26')]", 0)
        expectCount(#"[{"value":5.1}]"#, "$[?(@.value=='5.1.26')]", 0)

        expectCount(#"[{"value":"5.1.26"}]"#, "$[?(@.value=='5')]", 0)
        expectCount(#"[{"value":"5.1.26"}]"#, "$[?(@.value==5)]", 0)
        expectCount(#"[{"value":"5.1.26"}]"#, "$[?(@.value==5.1)]", 0)
    }

    @Test func test_lt_check_does_not_break_evaluation() throws {
        expectCount(#"[{"value":"5"}]"#, "$[?(@.value<'7')]", 1)

        expectCount(#"[{"value":"7"}]"#, "$[?(@.value<'5')]", 0)

        expectCount(#"[{"value":5}]"#, "$[?(@.value<7)]", 1)
        expectCount(#"[{"value":7}]"#, "$[?(@.value<5)]", 0)

        expectCount(#"[{"value":5}]"#, "$[?(@.value<7.1)]", 1)
        expectCount(#"[{"value":7}]"#, "$[?(@.value<5.1)]", 0)

        expectCount(#"[{"value":"5.1"}]"#, "$[?(@.value<7)]", 1)
        expectCount(#"[{"value":"7.1"}]"#, "$[?(@.value<5)]", 0)
    }

    @Test func test_escape_pattern() throws {
        expectCount("[\"x\"]", "$[?(@ =~ /\\/|x/)]", 1)
    }

    @Test func test_filter_evaluation_does_not_break_path_evaluation() throws {
        expectCount(
            "[{\"s\": \"fo\", \"expected_size\": \"m\"}, {\"s\": \"lo\", \"expected_size\": 2}]",
            "$[?(@.s size @.expected_size)]", 1)
    }
}
