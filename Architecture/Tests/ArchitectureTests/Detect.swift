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
        return scope.references(to: impureTypes) + calls.map(\.erased) + now.map(\.erased)
    }

    /// `import Foundation` anywhere but the `#else` of `#if canImport(FoundationEssentials)`.
    static func unguardedFoundationImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.imports(of: "Foundation").filter { match in
            guard let clause = match.node.enclosingIfConfigClauses.first else { return true }
            return !(clause.isElse && clause.ifCondition == "canImport(FoundationEssentials)")
        }
    }

    /// What `ArazzoKit` may import. Its only package dependency is swift-jsonpath.
    static let arazzoKitModules: Set<String> = ["JSONPath", "FoundationEssentials", "Foundation"]

    /// Imports in `ArazzoKit` outside its budget, and `import Yams` in `ArazzoKitYAML` outside `#if YAML`.
    static func importsOverBudget(arazzoKit: Scope, arazzoKitYAML: Scope) -> [Match<ImportDeclSyntax>] {
        let kit = arazzoKit.imports.filter { !arazzoKitModules.contains($0.node.moduleName) }
        let yams = arazzoKitYAML.imports(of: "Yams").filter { match in
            !match.node.enclosingIfConfigClauses.contains {
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

    /// `try` inside an `#expect` or `#require` argument that does not itself start with `try`. A `try` inside a
    /// closure argument is in a throwing closure, so it is not one.
    static func nestedTryInExpectations(in scope: Scope) -> [Match<TryExprSyntax>] {
        scope.containing("#expect", "#require").nodes(of: MacroExpansionExprSyntax.self) {
            ["expect", "require"].contains($0.node.macroName.text)
        }
        .flatMap { macro in
            macro.node.arguments.filter { !startsWithTry($0.expression) }
                .flatMap { TryFinder.tries(in: $0.expression) }
                .map { Match(node: $0, file: macro.file) }
        }
    }

    /// `try a == b` is not folded by the parser: it is a sequence whose first element is the `try`, which covers
    /// the whole expression.
    private static func startsWithTry(_ expression: ExprSyntax) -> Bool {
        if expression.is(TryExprSyntax.self) { return true }
        return expression.as(SequenceExprSyntax.self)?.elements.first?.is(TryExprSyntax.self) == true
    }
}

/// The `try` expressions under a node, outside closures.
private final class TryFinder: SyntaxVisitor {
    var found: [TryExprSyntax] = []

    static func tries(in node: some SyntaxProtocol) -> [TryExprSyntax] {
        let finder = TryFinder(viewMode: .sourceAccurate)
        finder.walk(node)
        return finder.found
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
