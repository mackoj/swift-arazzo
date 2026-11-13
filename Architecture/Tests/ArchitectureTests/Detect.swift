import LLMCheck
import SwiftSyntax

/// The detectors, separate from the codebase so `DetectorTests` can run them on snippets.
enum Detect {
    /// Types whose every use is I/O or shared global state.
    static let impureTypes: Set<String> = [
        "FileManager", "FileHandle", "URLSession", "ProcessInfo", "NotificationCenter", "UserDefaults", "Bundle",
        "DispatchQueue",
    ]

    /// Uses of I/O, a clock, randomness or a singleton: `FileManager.default`, `Date()`, `Date.now`, `UUID()`,
    /// `print(x)`. `Date(timeIntervalSince1970:)` and `UUID(uuidString:)` are pure and pass.
    static func impureCode(in scope: Scope) -> [Match<Syntax>] {
        let calls = scope.calls(named: "Date", "UUID", "print").filter { call in
            call.node.calledExpression.is(DeclReferenceExprSyntax.self)
                && (call.node.calledName == "print" || call.node.arguments.isEmpty)
        }
        let now = scope.containing("Date.now").nodes(of: MemberAccessExprSyntax.self) {
            $0.node.declName.baseName.text == "now" && $0.node.base?.trimmedDescription == "Date"
        }
        return scope.references(to: impureTypes) + calls.map { Match(node: Syntax($0.node), file: $0.file) }
            + now.map { Match(node: Syntax($0.node), file: $0.file) }
    }

    /// `import Foundation` anywhere but the `#else` of `#if canImport(FoundationEssentials)`.
    static func unguardedFoundationImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.containing("import Foundation").nodes(of: ImportDeclSyntax.self) { match in
            guard match.node.moduleName == "Foundation" else { return false }
            guard let clause = match.node.enclosingIfConfigClauses.first else { return true }
            return !(clause.isElse && clause.ifCondition == "canImport(FoundationEssentials)")
        }
    }

    /// What `ArazzoKit` may import. Its only package dependency is swift-jsonpath.
    static let arazzoKitModules: Set<String> = ["JSONPath", "FoundationEssentials", "Foundation"]

    /// Imports in `ArazzoKit` outside its budget, and `import Yams` in `ArazzoKitYAML` outside `#if YAML`.
    static func importsOverBudget(arazzoKit: Scope, arazzoKitYAML: Scope) -> [Match<ImportDeclSyntax>] {
        let kit = arazzoKit.nodes(of: ImportDeclSyntax.self) { !arazzoKitModules.contains($0.node.moduleName) }
        let yams = arazzoKitYAML.containing("Yams").nodes(of: ImportDeclSyntax.self) { match in
            guard match.node.moduleName == "Yams" else { return false }
            return !match.node.enclosingIfConfigClauses.contains {
                !$0.isElse && $0.condition?.trimmedDescription == "YAML"
            }
        }
        return kit + yams
    }

    /// Public structs and enums that are not declared `Hashable` and `Sendable`.
    static func publicTypesMissingConformances(in scope: Scope) -> [Declaration] {
        (scope.structs + scope.enums).withModifier("public").filter {
            !($0.inherits(from: "Hashable") && $0.inherits(from: "Sendable"))
        }
    }

    /// `@unchecked Sendable` conformances with no comment on the declaration that makes them.
    static func uncommentedUncheckedSendable(in scope: Scope) -> [Match<AttributeSyntax>] {
        scope.containing("@unchecked").nodes(of: AttributeSyntax.self) { match in
            guard match.node.attributeName.trimmedDescription == "unchecked" else { return false }
            let declaration = sequence(first: Syntax(match.node), next: \.parent).first { $0.is(DeclSyntax.self) }
            return declaration?.attachedComments.isEmpty ?? true
        }
    }

    /// `import XCTest`.
    static func xcTestImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.containing("XCTest").nodes(of: ImportDeclSyntax.self) { $0.node.moduleName == "XCTest" }
    }

    /// `withKnownIssue { … }` whose first argument is not a string literal: the reason.
    static func unexplainedKnownIssues(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
        scope.calls(named: "withKnownIssue").filter { call in
            guard let first = call.node.arguments.first, first.label == nil else { return true }
            return !first.expression.is(StringLiteralExprSyntax.self)
        }
    }

    /// The `.disabled(…)` trait, wherever a test or suite takes it.
    static func disabledTests(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
        scope.calls(named: "disabled").filter { call in
            call.node.receiver == nil && call.node.calledExpression.is(MemberAccessExprSyntax.self)
        }
    }
}
