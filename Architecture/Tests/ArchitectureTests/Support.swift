import LLMCheck
import SwiftSyntax

/// The swift-arazzo repository, rooted where `.llm-check.yaml` is. Its file list and every parsed file are shared by
/// all suites, which Swift Testing runs in parallel.
func arazzo() throws -> Codebase { try Codebase() }

extension RuleCategory {
    static let purity = RuleCategory(
        "purity",
        description: "The library is pure. Read before you reach for the file system, the network, a clock or a UUID."
    )
    static let platforms = RuleCategory(
        "platforms",
        description: "Imports and the dependency budget. Read before you add an `import` to `Sources`."
    )
    static let models = RuleCategory(
        "models",
        description: "Public types and concurrency. Read before you add or change a public type."
    )
    static let testing = RuleCategory(
        "testing",
        description: "Swift Testing, and no silenced tests. Read before you add, skip or mark a test."
    )
}

extension ImportDeclSyntax {
    /// `Foundation` in `import Foundation`, `Darwin` in `import Darwin.C`.
    var moduleName: String { path.first?.name.text ?? "" }
}

extension SyntaxProtocol {
    /// The `#if`, `#elseif` and `#else` clauses this node is in, innermost first.
    var enclosingIfConfigClauses: [IfConfigClauseSyntax] {
        sequence(first: Syntax(self), next: \.parent).compactMap { $0.as(IfConfigClauseSyntax.self) }
    }
}

extension IfConfigClauseSyntax {
    /// The condition of the `#if` this clause belongs to: `canImport(FoundationEssentials)` for the `#else` of
    /// `#if canImport(FoundationEssentials)`.
    var ifCondition: String? {
        parent?.as(IfConfigClauseListSyntax.self)?.first?.condition?.trimmedDescription
    }

    var isElse: Bool { poundKeyword.tokenKind == .poundElse }
}
