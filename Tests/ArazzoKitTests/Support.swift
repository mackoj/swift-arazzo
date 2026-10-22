import ArazzoKit
import ArazzoKitYAML
import Foundation
import Testing

enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// The Arazzo 1.0.0 examples published in the OAI/Arazzo-Specification repository.
    static let official10 = [
        "ExtendedParametersExample.arazzo.yaml",
        "FAPI-PAR.arazzo.yaml",
        "LoginAndRetrievePets.arazzo.yaml",
        "bnpl-arazzo.yaml",
        "oauth.arazzo.yaml",
        "pet-coupons.arazzo.yaml",
    ]

    static let all = official10 + [
        "pet-purchase-spec-example-1.1.arazzo.yaml",
        "async-order-1.1.arazzo.yaml",
    ]

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    static func document(_ name: String, strict: Bool = false) throws -> Arazzo.Document {
        try Arazzo.Document(yaml: try text(name), options: .init(strict: strict))
    }
}

func decodeYAML<T: Decodable>(_ type: T.Type, _ yaml: String, strict: Bool = false) throws -> T {
    try ArazzoYAML.decode(type, from: yaml, options: .init(strict: strict))
}

/// A minimal valid document to start validation scenarios from.
func makeDocument(
    arazzo: Arazzo.SpecificationVersion = .v1_1_0,
    sources: [Arazzo.SourceDescription] = [.init(name: "api", url: "./openapi.yaml", type: .openapi)],
    workflows: [Arazzo.Workflow],
    components: Arazzo.Components = .init()
) -> Arazzo.Document {
    Arazzo.Document(
        arazzo: arazzo,
        info: .init(title: "Test", version: "1.0.0"),
        sourceDescriptions: sources,
        workflows: workflows,
        components: components)
}

func expression(_ string: String) -> Arazzo.RuntimeExpression {
    try! Arazzo.RuntimeExpression(string)
}

extension Array where Element == Arazzo.ValidationIssue {
    var errors: [Arazzo.ValidationIssue] { filter { $0.severity == .error } }
    var warnings: [Arazzo.ValidationIssue] { filter { $0.severity == .warning } }

    func contains(rule: String, path: String? = nil, severity: Arazzo.ValidationIssue.Severity? = nil) -> Bool {
        contains { issue in
            issue.rule == rule && (path == nil || issue.path == path) && (severity == nil || issue.severity == severity)
        }
    }
}
