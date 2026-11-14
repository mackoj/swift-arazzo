import LLMCheck
import Testing

/// Each detector on snippets: it finds what its rule forbids and nothing its rule allows.
@Suite struct DetectorTests {
    func scope(_ source: String, at path: String = "Sources/ArazzoKit/File.swift") -> Scope {
        Scope(files: [SourceFile(path: path, source: source)])
    }

    @Test func impureCodeIsFound() {
        let found = Detect.impureCode(
            in: scope(
                """
                let files = FileManager.default
                let now = Date()
                let later = Date.now
                let id = UUID()
                print("decoded")
                func load(_ session: URLSession) {}
                """))
        #expect(found.map(\.location.line).sorted() == [1, 2, 3, 4, 5, 6])
    }

    @Test func pureCodePasses() {
        let found = Detect.impureCode(
            in: scope(
                """
                // FileManager and URLSession are fine in a comment.
                let message = "Date() and print() are fine in a string"
                let epoch = Date(timeIntervalSince1970: 0)
                let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
                reporter.print(issue)
                """))
        #expect(found.isEmpty)
    }

    @Test func unguardedFoundationIsFound() {
        let found = Detect.unguardedFoundationImports(
            in: scope(
                """
                import Foundation
                #if canImport(Darwin)
                import Foundation
                #endif
                #if canImport(FoundationEssentials)
                import Foundation
                #endif
                """))
        #expect(found.map(\.location.line) == [1, 3, 6])
    }

    @Test func guardedFoundationPasses() {
        let found = Detect.unguardedFoundationImports(
            in: scope(
                """
                #if canImport(FoundationEssentials)
                import FoundationEssentials
                #else
                import Foundation
                #endif
                """))
        #expect(found.isEmpty)
    }

    @Test func importsOverBudgetAreFound() {
        let found = Detect.importsOverBudget(
            arazzoKit: scope("import JSONPath\nimport Yams\nimport OrderedCollections"),
            arazzoKitYAML: scope("import ArazzoKit\nimport Yams", at: "Sources/ArazzoKitYAML/ArazzoYAML.swift"))
        #expect(found.map(\.node.moduleName) == ["Yams", "OrderedCollections", "Yams"])
    }

    @Test func importsWithinBudgetPass() {
        let found = Detect.importsOverBudget(
            arazzoKit: scope(
                """
                import JSONPath
                #if canImport(FoundationEssentials)
                import FoundationEssentials
                #else
                import Foundation
                #endif
                """),
            arazzoKitYAML: scope(
                """
                #if YAML
                import ArazzoKit
                import Yams
                #if canImport(FoundationEssentials)
                import FoundationEssentials
                #endif
                #endif
                """, at: "Sources/ArazzoKitYAML/ArazzoYAML.swift"))
        #expect(found.isEmpty)
    }

    @Test func missingConformancesAreFound() {
        let found = Detect.publicTypesMissingConformances(
            in: scope(
                """
                public struct Criterion: VendorExtendable {
                    public enum Kind: Hashable { case simple }
                }
                public struct Step: Hashable, Sendable {}
                struct Internal {}
                """))
        #expect(found.map(\.qualifiedName) == ["Criterion", "Criterion.Kind"])
    }

    @Test func nestedTryInExpectationsIsFound() {
        let found = Detect.nestedTryInExpectations(
            in: scope(
                """
                #expect(condition == .expression(try .init("$statusCode"), accessors: []))
                #expect(try parse("a") == try parse("b"))
                #require(try value())
                #expect(throws: ParseError.self) { try parse("") }
                #expect(values.map { try? parse($0) } == [nil])
                #require(Int(try text()) != nil)
                """, at: "Tests/T/A.swift"))
        #expect(found.map(\.location.line) == [1, 6])
    }
}
