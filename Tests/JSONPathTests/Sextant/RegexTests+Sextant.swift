// Ported from Sextant (https://github.com/KittyMac/Sextant), MIT License, Copyright (c) 2021 Rocco Bowling.
// Source: Tests/SextantTests/Jayway/PatternFlagTest.swift, RegexpEvaluatorTest.swift.
//
// Adaptations: Sextant maps flags to NSRegularExpression options; we use Swift Regex inline options,
// so `d`, `u` and `U` are accepted and ignored. Sextant's ValueNode types map to `JaywayValue`.
// Sextant's "PathNode" case (an unevaluated path used as a regex subject) has no equivalent: paths are
// always resolved before comparison.

@testable import JSONPath
import Testing

@Suite("Sextant: PatternFlag")
struct PatternFlagTestPorted {
    @Test(arguments: [
        ("d", ""), ("i", "i"), ("x", "x"), ("m", "m"), ("xmsU", "msx"), ("dxm", "mx"), ("dix", "ix"),
        ("xsu", "sx"), ("dixmsuU", "imsx"),
    ])
    func testParseFlags(_ flags: String, _ expected: String) {
        #expect(String(JaywayRegex.options(flags).sorted()) == expected)
    }
}

@Suite("Sextant: RegexpEvaluator")
struct RegexpEvaluatorTestPorted {
    func check(_ regex: String, _ value: JaywayValue, _ expected: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        let slash = regex.lastIndex(of: "/")!
        let pattern = String(regex[regex.index(after: regex.startIndex)..<slash])
        let flags = String(regex[regex.index(after: slash)...])
        let result = JaywayValue.evaluate(.pattern(pattern: pattern, flags: flags), .regex, value)
        #expect(result != .error, sourceLocation: sourceLocation)
        #expect((result == .true) == expected, sourceLocation: sourceLocation)
    }

    @Test func test_should_evaluate_regular_expression() throws {
        check("/true|false/", .string("true"), true)
        check("/9.*9/", .number(9979, description: "9979"), true)
        check("/fa.*se/", .bool(false), true)
        check("/JsonNode/", JaywayValue(try JSONValue(parsing: #"{ "some": "JsonNode" }"#)), true)
        check("/NullNode/", .null, false)
        check("/test/i", .string("tEsT"), true)
        check("/test/", .string("tEsT"), false)
        check(#"/Þ/ui"#, .string("\u{fe}"), true)
        check(#"/Þ/"#, .string("\u{fe}"), false)
        check("/test# code/", .string("test"), false)
        check("/test# code/x", .string("test"), true)
    }

    @Test func regexInFilters() throws {
        expectCount(#"[{"v": 9979}, {"v": "true"}, {"v": false}, {"v": null}]"#, "$[?(@.v =~ /9.*9|true|fa.*se|null/)]", 3)
    }
}
