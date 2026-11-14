import LLMCheck

extension Rule {
    static let libraryPerformsNoIO = Rule(
        id: "library-performs-no-io",
        title: "The library performs no I/O, reads no clock, makes no UUID and touches no singleton.",
        category: .purity,
        rationale: """
            swift-arazzo is a pure library (CODING_STANDARDS.md, "Pure library"): callers pass data in and get values \
            back, so the same input gives the same output on every platform and in every test. A file read, a network \
            call, `Date()`, `UUID()`, a `.shared` or `.default` singleton or `print` makes results depend on the \
            machine, and `print` writes to a host's standard output.
            """,
        howToFix: """
            Take the value as a parameter, or add an extension point the caller conforms to, like `QueryEvaluator` or \
            `RuntimeExpressionResolver`. Report a problem as a thrown error or a `ValidationIssue`, never by printing.
            """,
        badExample: """
            let document = try Arazzo.Document(json: Data(contentsOf: url))  // Data(contentsOf:) reads via FileManager
            let runID = UUID()
            """,
        goodExample: """
            public init(json data: Data, options: Arazzo.DecodingOptions = .init()) throws  // the caller reads the file
            public func evaluate(in context: some RuntimeExpressionResolver) throws -> Bool  // the caller supplies state
            """
    )

    static let foundationFallsBackFromEssentials = Rule(
        id: "foundation-falls-back-from-essentials",
        title: "`import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)`.",
        category: .platforms,
        rationale: """
            On Linux, FoundationEssentials is the small, Codable-only part of swift-foundation; full Foundation pulls \
            in ICU and everything else. The library needs only the essentials, so it imports them where they exist \
            and falls back to Foundation elsewhere (CONSTRAINTS.md, "ArazzoKit dependency budget").
            """,
        howToFix: "Wrap the import in the same guard as `Sources/ArazzoKit/Model/Document.swift`.",
        badExample: "import Foundation",
        goodExample: """
            #if canImport(FoundationEssentials)
            import FoundationEssentials
            #else
            import Foundation
            #endif
            """
    )

    static let importsStayWithinBudget = Rule(
        id: "imports-stay-within-budget",
        title: """
            ArazzoKit imports only JSONPath and Foundation, ArazzoKitBuilder only ArazzoKit; Yams is imported only \
            under `#if YAML`.
            """,
        category: .platforms,
        rationale: """
            ArazzoKit's dependency budget is swift-jsonpath alone, and YAML support stays behind the `YAML` package \
            trait so a client that turns the trait off never builds Yams (CONSTRAINTS.md, "ArazzoKit dependency \
            budget"). An extra import in ArazzoKit is an extra dependency for every client. ArazzoKitBuilder is a \
            layer over ArazzoKit's value types: anything more would cost its users a dependency they did not choose.
            """,
        howToFix: """
            Implement the feature with the standard library, FoundationEssentials or JSONPath. Code that needs Yams \
            belongs in ArazzoKitYAML, inside its `#if YAML` block, and ArazzoKitBuilder reaches JSONPath through \
            ArazzoKit's re-export. A new dependency is a decision for the maintainer, \
            recorded in `Package.swift`, `Package@swift-6.0.swift` and CONSTRAINTS.md first.
            """,
        badExample: """
            // Sources/ArazzoKit/Model/Document.swift
            import Yams
            """,
        goodExample: """
            // Sources/ArazzoKitYAML/ArazzoYAML.swift
            #if YAML
            import ArazzoKit
            import Yams
            """
    )

    static let publicModelsAreHashableAndSendable = Rule(
        id: "public-models-are-hashable-and-sendable",
        title: "A public struct or enum in `Sources/ArazzoKit/Model` is declared `Hashable` and `Sendable`.",
        category: .models,
        rationale: """
            Models are values (CODING_STANDARDS.md, "Sendable value types"): `Sendable` lets clients share a decoded \
            document across tasks under Swift 6, and `Hashable` lets tests compare whole documents rather than \
            fields one by one. A missing conformance is a source break to add later, since a client cannot add it.
            """,
        howToFix: "Declare both on the type itself, like its neighbours: `public struct Step: Hashable, Sendable, …`.",
        badExample: "public struct Criterion: VendorExtendable {",
        goodExample: "public struct Criterion: Hashable, Sendable, VendorExtendable {"
    )

    static let uncheckedSendableExplainsItself = Rule(
        id: "unchecked-sendable-explains-itself",
        title: "An `@unchecked Sendable` conformance has a comment that proves it safe.",
        category: .models,
        rationale: """
            `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only \
            proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types"); shared mutable \
            state belongs in an `actor` instead.
            """,
        howToFix: """
            Prefer a value type or an `actor`. If neither fits, put a `//` comment (not a `///` doc comment) just \
            above the declaration, or at the start of its body, that says what guards the mutable state.
            """,
        badExample: "final class Cache: @unchecked Sendable {",
        goodExample: """
            // Every access to `storage` holds `lock`.
            final class Cache: @unchecked Sendable {
            """
    )

    static let testsUseSwiftTesting = Rule(
        id: "tests-use-swift-testing",
        title: "Tests use Swift Testing, never XCTest.",
        category: .testing,
        rationale: """
            The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and \
            `#require` give one failure message style, parameterised tests and parallel, randomly ordered runs.
            """,
        howToFix: "Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.",
        badExample: """
            import XCTest
            final class ConditionTests: XCTestCase { func testEquality() { XCTAssertTrue(…) } }
            """,
        goodExample: """
            import Testing
            @Suite struct ConditionTests { @Test func equality() { #expect(…) } }
            """
    )

    static let knownIssuesExplainThemselves = Rule(
        id: "known-issues-explain-themselves",
        title: "`withKnownIssue` names the issue that tracks it.",
        category: .testing,
        rationale: """
            A known issue hides a failing expectation. Without a reason and a link, the next reader cannot tell a bug \
            waiting for a fix from a test nobody understood, and nobody removes it once the bug is fixed \
            (CONSTRAINTS.md, "Floor").
            """,
        howToFix: "Pass the reason as the first argument, with the GitHub issue that tracks it.",
        badExample: "withKnownIssue { try validate(document) }",
        goodExample: """
            withKnownIssue("Upstream example uses a 1.1 field in a 1.0 document (mackoj/swift-arazzo#12)") {
                try validate(document)
            }
            """
    )

    static let testsAreNotDisabled = Rule(
        id: "tests-are-not-disabled",
        title: "No test or suite is `.disabled`.",
        category: .testing,
        rationale: """
            A disabled test still reads as coverage while checking nothing (CONSTRAINTS.md, "Floor"). A failing \
            behaviour is either fixed, or asserted as a known issue that names its tracking issue.
            """,
        howToFix: "Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue(\"…#N\")`.",
        badExample: "@Test(.disabled(\"flaky\")) func decodesExample() throws {",
        goodExample: "@Test func decodesExample() throws {"
    )
}

extension Rule {
    static let tryLeadsExpectations = Rule(
        id: "try-leads-expectations",
        title: "In `#expect` and `#require`, `try` comes first or not at all.",
        category: .testing,
        rationale: """
            CI builds the tests on Swift 6.0 (CONSTRAINTS.md), whose `#expect` and `#require` expand the expression \
            into a non-throwing autoclosure unless it starts with `try`. A `try` nested inside it, such as \
            `#expect(x == .y(try z()))`, compiles on Swift 6.1 and later and fails on 6.0 with "call can throw, but \
            it is executed in a non-throwing autoclosure".
            """,
        howToFix: "Compute the throwing value in a `let` before the expectation, or start the expression with `try`.",
        badExample: """
            #expect(condition == .expression(try .init("$statusCode"), accessors: []))
            """,
        goodExample: """
            let statusCode = try Arazzo.RuntimeExpression("$statusCode")
            #expect(condition == .expression(statusCode, accessors: []))
            """
    )
}

/// Every rule, in the order `docs/architecture-rules.md` lists them.
let allRules: [Rule] = [
    .libraryPerformsNoIO, .foundationFallsBackFromEssentials, .importsStayWithinBudget,
    .publicModelsAreHashableAndSendable, .uncheckedSendableExplainsItself, .testsUseSwiftTesting,
    .knownIssuesExplainThemselves, .testsAreNotDisabled, .tryLeadsExpectations,
]
