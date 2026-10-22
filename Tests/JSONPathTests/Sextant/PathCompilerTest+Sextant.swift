// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Source: Tests/SextantTests/Jayway/PathCompilerTest.swift, FilterCompilerTest.swift, FilterParseTest.swift,
// PathTokenTest.swift.
//
// Adaptations: Sextant's `PathCompiler.compile(query:)` / `FilterCompiler.compile(filter:)` map to
// `JSONPath(_:dialect: .jayway)` and its `description`. Sextant prints filters as `[?]` and function
// arguments as `(...)` inside paths; ArazzoKit's JSONPath prints them in full so descriptions can be
// parsed back.

import JSONPath
import Testing

private func compile(_ path: String) -> String? {
    (try? JSONPath(path, dialect: .jayway))?.description
}

/// Sextant compiles standalone filters such as `[?(@.foo)]`; we compile them as `$[?(@.foo)]`.
private func compileFilter(_ filter: String) -> String? {
    compile("$" + filter).map { String($0.dropFirst()) }
}

@Suite("Sextant: PathCompiler")
struct PathCompilerTestPorted: SextantTestCase {
    @Test func test_a_root_path_must_be_followed_by_period_or_bracket() {
        #expect(compile("$X") == nil)
    }

    @Test func test_a_root_path_can_be_compiled() {
        #expect(compile("$") == "$")
        #expect(compile("@") == "@")
    }

    @Test func test_a_path_may_not_end_with_period() {
        #expect(compile("$.") == nil)
        #expect(compile("$.prop.") == nil)
    }

    @Test func test_a_path_may_not_end_with_scan() {
        #expect(compile("$..") == nil)
        #expect(compile("$.prop..") == nil)
    }

    @Test func test_a_property_token_can_be_compiled() {
        #expect(compile("$.prop") == "$['prop']")
        #expect(compile("$.1prop") == "$['1prop']")
        #expect(compile("$.@prop") == "$['@prop']")
    }

    @Test func test_a_bracket_notation_property_token_can_be_compiled() {
        #expect(compile("$['prop']") == "$['prop']")
        #expect(compile("$['1prop']") == "$['1prop']")
        #expect(compile("$['@prop']") == "$['@prop']")
        #expect(compile("$[  '@prop'  ]") == "$['@prop']")
        #expect(compile("$[\"prop\"]") == "$[\"prop\"]")
    }

    @Test func test_a_multi_property_token_can_be_compiled() {
        #expect(compile("$['prop0', 'prop1']") == "$['prop0','prop1']")
        #expect(compile("$[  'prop0'  , 'prop1'  ]") == "$['prop0','prop1']")
    }

    @Test func test_a_property_chain_can_be_compiled() {
        #expect(compile("$.abc") == "$['abc']")
        #expect(compile("$.aaa.bbb") == "$['aaa']['bbb']")
        #expect(compile("$.aaa.bbb.ccc") == "$['aaa']['bbb']['ccc']")
    }

    @Test func test_a_property_may_not_contain_blanks() {
        #expect(compile("$.foo bar") == nil)
    }

    @Test func test_a_wildcard_can_be_compiled() {
        #expect(compile("$.*") == "$[*]")
        #expect(compile("$[*]") == "$[*]")
        #expect(compile("$[ * ]") == "$[*]")
    }

    @Test func test_a_wildcard_can_follow_a_property() {
        #expect(compile("$.prop[*]") == "$['prop'][*]")
        #expect(compile("$['prop'][*]") == "$['prop'][*]")
    }

    @Test func test_an_array_index_path_can_be_compiled() {
        #expect(compile("$[1]") == "$[1]")
        #expect(compile("$[1,2,3]") == "$[1,2,3]")
        #expect(compile("$[ 1 , 2 , 3 ]") == "$[1,2,3]")
    }

    @Test func test_an_array_slice_path_can_be_compiled() {
        #expect(compile("$[-1:]") == "$[-1:]")
        #expect(compile("$[1:2]") == "$[1:2]")
        #expect(compile("$[:2]") == "$[:2]")
    }

    @Test func test_a_scan_token_can_be_parsed() {
        #expect(compile("$..['prop']..[*]") == "$..['prop']..[*]")
    }

    @Test func test_list_syntax_errors() {
        #expect(compile("$[0, 1, 2 4]") == nil)  // indexes must be separated by commas
        #expect(compile("$['1','2',]") == nil)  // trailing comma
        #expect(compile("$['1', ,'3']") == nil)  // double comma
        #expect(compile("$['aaa'}'bbb']") == nil)  // properties must be separated by commas
    }

    @Test func test_an_inline_criteria_can_be_parsed() {
        // Adapted: Sextant prints `$[?]`.
        #expect(compile("$[?(@.foo == 'bar')]") == "$[?(@['foo'] == 'bar')]")
        #expect(compile("$[?(@.foo == \"bar\")]") == "$[?(@['foo'] == \"bar\")]")
    }

    @Test func test_issue_predicate_can_have_escaped_backslash_in_prop() {
        let json = #"{"logs":[{"message":"it\\\r\n\\","id":2}]}"#
        expectValues(json, #"$.logs[?(@.message == 'it\\\r\n\\')].message"#, ["it\\\r\n\\"])
        expectPaths(json, #"$.logs[?(@.message == 'it\\\r\n\\')].message"#, [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_bracket_in_regex() {
        let json = #"{"logs":[{"message":"(it","id":2}]}"#
        expectValues(json, "$.logs[?(@.message =~ /\\(it/)].message", ["(it"])
        expectPaths(json, "$.logs[?(@.message =~ /\\(it/)].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_and_in_regex() {
        let json = #"{"logs":[{"message":"it","id":2}]}"#
        expectValues(json, "$.logs[?(@.message =~ /&&|it/)].message", ["it"])
        expectPaths(json, "$.logs[?(@.message =~ /&&|it/)].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_and_in_prop() {
        let json = #"{"logs":[{"message":"&& it","id":2}]}"#
        expectValues(json, "$.logs[?(@.message == '&& it')].message", ["&& it"])
        expectPaths(json, "$.logs[?(@.message == '&& it')].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_brackets_must_change_priorities() {
        let json = #"{"logs":[{"id":2}]}"#
        expectCount(json, "$.logs[?(@.message && (@.id == 1 || @.id == 2))].id", 0)
        expectCount(json, "$.logs[?((@.id == 2 || @.id == 1) && @.message)].id", 0)
    }

    @Test func test_issue_predicate_or_has_lower_priority_than_and() {
        let json = #"{"logs":[{"id":2}]}"#
        expectCount(json, "$.logs[?(@.x && @.y || @.id)]", 1)
        expectPaths(json, "$.logs[?(@.x && @.y || @.id)]", ["$['logs'][0]"])
    }

    @Test func test_issue_predicate_can_have_double_quotes() {
        let json = #"{"logs":[{"message":"\"it\"","id":2}]}"#
        expectValues(json, "$.logs[?(@.message == '\"it\"')].message", [#""it""#])
        expectPaths(json, "$.logs[?(@.message == '\"it\"')].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_single_quotes() {
        let json = #"{"logs":[{"message":"'it'","id":2}]}"#
        expectValues(json, "$.logs[?(@.message == \"'it'\")].message", ["'it'"])
        expectPaths(json, "$.logs[?(@.message == \"'it'\")].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_single_quotes_escaped() {
        let json = #"{"logs":[{"message":"'it'","id":2}]}"#
        expectValues(json, "$.logs[?(@.message == '\\'it\\'')].message", ["'it'"])
        expectPaths(json, "$.logs[?(@.message == '\\'it\\'')].message", [#"$['logs'][0]['message']"#])
    }

    @Test func test_issue_predicate_can_have_square_bracket_in_prop() {
        let json = #"{"logs":[{"message":"] it","id":2}]}"#
        expectValues(json, "$.logs[?(@.message == '] it')].message", ["] it"])
        expectPaths(json, "$.logs[?(@.message == '] it')].message", ["$['logs'][0]['message']"])
    }

    @Test func test_a_function_can_be_compiled() {
        // Adapted: Sextant prints arguments as `(...)`.
        #expect(compile("$.aaa.foo()") == "$['aaa'].foo()")
        #expect(compile("$.aaa.foo(5)") == "$['aaa'].foo(5)")
        #expect(compile("$.aaa.foo($.bar)") == "$['aaa'].foo($['bar'])")
        #expect(compile("$.aaa.foo(5,10,15)") == "$['aaa'].foo(5,10,15)")
    }

    @Test func test_an_unknown_function_fails_at_evaluation() {
        // Sextant compiles unknown functions and fails when evaluating them.
        expectInvalid(#"{"aaa": [1]}"#, "$.aaa.foo()")
    }
}

@Suite("Sextant: FilterCompiler")
struct FilterCompilerTestPorted {
    @Test(arguments: [
        ("[?($['firstname']['str_eq'] == '')]", "[?($['firstname']['str_eq'] == '')]"),
        ("[?(@)]", "[?(@)]"),
        ("[?(@.firstname)]", "[?(@['firstname'])]"),
        ("[?($.firstname)]", "[?($['firstname'])]"),
        ("[?(@['firstname'])]", "[?(@['firstname'])]"),
        ("[?($['firstname'].lastname)]", "[?($['firstname']['lastname'])]"),
        ("[?($['firstname']['lastname'])]", "[?($['firstname']['lastname'])]"),
        ("[?($['firstname']['lastname'].*)]", "[?($['firstname']['lastname'][*])]"),
        ("[?($['firstname']['num_eq'] == 1)]", "[?($['firstname']['num_eq'] == 1)]"),
        ("[?($['firstname']['num_gt'] > 1.1)]", "[?($['firstname']['num_gt'] > 1.1)]"),
        ("[?($['firstname']['num_lt'] < 11.11)]", "[?($['firstname']['num_lt'] < 11.11)]"),
        ("[?($['firstname']['str_eq'] == 'hej')]", "[?($['firstname']['str_eq'] == 'hej')]"),
        ("[?($['firstname']['str_eq'] == null)]", "[?($['firstname']['str_eq'] == null)]"),
        ("[?($['firstname']['str_eq'] == true)]", "[?($['firstname']['str_eq'] == true)]"),
        ("[?($['firstname']['str_eq'] == false)]", "[?($['firstname']['str_eq'] == false)]"),
        ("[?(@.firstname && @.lastname)]", "[?(@['firstname'] && @['lastname'])]"),
        ("[?((@.firstname || @.lastname) && @.and)]", "[?((@['firstname'] || @['lastname']) && @['and'])]"),
        ("[?((@.a || @.b || @.c) && @.x)]", "[?((@['a'] || @['b'] || @['c']) && @['x'])]"),
        ("[?((@.a && @.b && @.c) || @.x)]", "[?((@['a'] && @['b'] && @['c']) || @['x'])]"),
        ("[?((@.a && @.b || @.c) || @.x)]", "[?(((@['a'] && @['b']) || @['c']) || @['x'])]"),
        ("[?((@.a && @.b) || (@.c && @.d))]", "[?((@['a'] && @['b']) || (@['c'] && @['d']))]"),
        ("[?(@.a IN [1,2,3])]", "[?(@['a'] IN [1,2,3])]"),
        ("[?(@.a IN {'foo':'bar'})]", "[?(@['a'] IN {'foo':'bar'})]"),
        ("[?(@.value<'7')]", "[?(@['value'] < '7')]"),
        ("[?(@.message == 'it\\\\')]", "[?(@['message'] == 'it\\\\')]"),
        ("[?(@.message.min() > 10)]", "[?(@['message'].min() > 10)]"),
        ("[?(@.message.min()==10)]", "[?(@['message'].min() == 10)]"),
        ("[?(10 == @.message.min())]", "[?(10 == @['message'].min())]"),
        ("[?(((@)))]", "[?(@)]"),
        ("[?(@.name =~ /.*?/i)]", "[?(@['name'] =~ /.*?/i)]"),
        ("[?(@.name =~ /.*?/)]", "[?(@['name'] =~ /.*?/)]"),
        ("[?($[\"firstname\"][\"lastname\"])]", "[?($[\"firstname\"][\"lastname\"])]"),
        ("[?($[\"firstname\"].lastname)]", "[?($[\"firstname\"]['lastname'])]"),
        ("[?($[\"firstname\", \"lastname\"])]", "[?($[\"firstname\",\"lastname\"])]"),
        ("[?(((@.a && @.b || @.c)) || @.x)]", "[?(((@['a'] && @['b']) || @['c']) || @['x'])]"),
        // test_string_quote_style_is_serialized
        ("[?('apa' == 'apa')]", "[?('apa' == 'apa')]"),
        ("[?('apa' == \"apa\")]", "[?('apa' == \"apa\")]"),
        // test_string_can_contain_path_chars
        ("[?(@[')]@$)]'] == ')]@$)]')]", "[?(@[')]@$)]'] == ')]@$)]')]"),
        ("[?(@[\")]@$)]\"] == \")]@$)]\")]", "[?(@[\")]@$)]\"] == \")]@$)]\")]"),
        // test_or_has_lower_priority_than_and
        (
            "[?(@.category == 'fiction' && @.author == 'Evelyn Waugh' || @.price > 15)]",
            "[?((@['category'] == 'fiction' && @['author'] == 'Evelyn Waugh') || @['price'] > 15)]"
        ),
        // test_not_exists_filter
        ("[?(!@.foo)]", "[?(!@['foo'])]"),
    ])
    func test_valid_filters_compile(_ filter: String, _ expected: String) {
        #expect(compileFilter(filter) == expected)
    }

    @Test(arguments: [
        "[?(@.foo == x)]",  // test_invalid_path_when_string_literal_is_unquoted
        "[?(@))]", "[?(@ FOO 1)]", "[?(@ || )]", "[?(@ == 'foo )]", "[?(@ == 1' )]", "[?(@.foo bar == 1)]",
        "[?(@.i == 5 @.i == 8)]", "[?(!5)]", "[?(!'foo')]",
    ])
    func test_invalid_filters_does_not_compile(_ filter: String) {
        #expect(compileFilter(filter) == nil)
    }
}

@Suite("Sextant: FilterParse")
struct FilterParseTestPorted {
    @Test(arguments: ["[?(@.foo)]", "[?(@.foo == 1)]", "[?(@.foo == 1 || @['bar'])]", "[?(@.foo == 1 && @['bar'])]"])
    func test_a_filter_can_be_parsed(_ filter: String) {
        #expect(compileFilter(filter) != nil)
    }

    @Test(arguments: ["[?(@.foo == 1)", "[?(@.foo == 1) ||]", "[(@.foo == 1)]", "[?@.foo == 1)]"])
    func test_an_invalid_filter_can_not_be_parsed(_ filter: String) {
        #expect(compileFilter(filter) == nil)
    }
}

/// Adapted from PathTokenTest: Sextant checks the internal `isUpstreamDefinite()` of token chains;
/// we check the public `isSingular` (Jayway "definite path") of equivalent paths.
@Suite("Sextant: PathToken")
struct PathTokenTestPorted {
    @Test(arguments: [
        ("$.foo", true), ("$.foo.bar.baz", true), ("$[0].bar", true), ("$.foo.length()", true),
        ("$.*.bar", false), ("$..bar", false), ("$['foo','foo2'].bar", false), ("$[?(@.a)].bar", false),
        ("$[1:2]", false),
    ])
    func definiteness(_ path: String, _ definite: Bool) throws {
        #expect(try JSONPath(path, dialect: .jayway).isSingular == definite)
    }
}
