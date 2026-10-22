import Foundation
import JSONPath
import Testing

/// Runs the official JSONPath Compliance Test Suite (RFC 9535) against the `.rfc9535` dialect.
@Suite("RFC 9535 compliance test suite")
struct ComplianceTestSuite {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let selector: String
        let document: JSONValue?
        let invalid: Bool
        /// One or more acceptable results (object member order may vary).
        let results: [[JSONValue]]
        let paths: [[String]]

        var testDescription: String { name }
    }

    static let cases: [Case] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/cts.json")
        let suite = try! JSONValue(parsing: Data(contentsOf: url))
        return suite["tests"]!.arrayValue!.map { test in
            let results: [[JSONValue]] =
                test["result"].map { [$0.arrayValue!] } ?? test["results"]?.arrayValue?.map { $0.arrayValue! } ?? []
            let paths: [[String]] =
                test["result_paths"].map { [$0.arrayValue!.compactMap(\.stringValue)] }
                ?? test["results_paths"]?.arrayValue?.map { $0.arrayValue!.compactMap(\.stringValue) } ?? []
            return Case(
                name: test["name"]!.stringValue!, selector: test["selector"]!.stringValue!, document: test["document"],
                invalid: test["invalid_selector"]?.boolValue == true, results: results, paths: paths)
        }
    }()

    @Test(arguments: cases)
    func compliance(_ test: Case) throws {
        if test.invalid {
            #expect(throws: JSONPath.ParseError.self, "\(test.selector) should be rejected") {
                try JSONPath(test.selector)
            }
            return
        }
        let path = try JSONPath(test.selector)
        let nodes = try path.nodes(in: test.document ?? .null)
        let values = nodes.map(\.value)
        #expect(
            test.results.contains { expected in
                expected.count == values.count && zip(expected, values).allSatisfy { $0.isDeepEqual(to: $1) }
            }, "\(test.selector) → \(values)")
        if !test.paths.isEmpty {
            let actual = nodes.compactMap(\.location).map(\.description)
            #expect(test.paths.contains(actual), "\(test.selector) paths → \(actual)")
        }
    }

    @Test func suiteIsComplete() {
        #expect(Self.cases.count >= 700)
    }
}
