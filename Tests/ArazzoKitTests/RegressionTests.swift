import ArazzoKit
import Foundation
import Testing

/// Regressions found by an independent review of the package.
@Suite("Review regressions")
struct RegressionTests {
    @Test func numericStringsCompareAsNumbers() throws {
        let context = Arazzo.EvaluationContext(response: .init(headers: ["a": "10", "b": "9", "hex": "0x10"]))
        #expect(try Arazzo.Condition("$response.header.a > $response.header.b").evaluate(in: context))
        #expect(try Arazzo.Condition("$response.header.b < $response.header.a").evaluate(in: context))
        // Only JSON-style numbers are coerced.
        #expect(try !Arazzo.Condition("$response.header.hex == 16").evaluate(in: context))
        #expect(try !Arazzo.Condition("'nan' == 'NaN' && 'nan' < 1").evaluate(in: context))
        // Integers compare exactly (no Double rounding).
        #expect(try !Arazzo.Condition("9007199254740993 == 9007199254740992").evaluate(in: context))
        #expect(try Arazzo.Condition("'9007199254740993' > 9007199254740992").evaluate(in: context))
    }

    @Test(arguments: ["$response.body##/a", "$inputs.a##/b", "$response.body['a]", "$response.body[a']"])
    func malformedExpressionsAreRejected(_ text: String) {
        #expect(throws: Arazzo.RuntimeExpression.ParseError.self) { try Arazzo.RuntimeExpression(text) }
    }

    @Test func emptyReplacementTargetIsTheWholePayload() throws {
        let body = Arazzo.RequestBody(
            contentType: "application/json", payload: ["a": 1], replacements: [.init(target: "", value: .literal(["b": 2]))])
        let document = makeDocument(workflows: [
            .init(workflowId: "w", steps: [.init(stepId: "s", target: .operationId("op"), requestBody: body)])
        ])
        #expect(!document.validate().contains(rule: "payload-replacements"))
        #expect(try body.resolvedPayload(in: Arazzo.EvaluationContext()) == ["b": 2])
    }

    @Test func simpleTypeWithoutContextIsOnlyAWarning() {
        let document = makeDocument(workflows: [
            .init(
                workflowId: "w",
                steps: [
                    .init(
                        stepId: "s", target: .operationId("op"),
                        successCriteria: [.init(condition: "$statusCode == 200", type: .simple)])
                ])
        ])
        let issues = document.validate()
        #expect(issues.contains(rule: "criteria", path: "/workflows/0/steps/0/successCriteria/0/context", severity: .warning))
        #expect(issues.errors.isEmpty)
    }

    @Test func jsonDecodingAndEncodingPreserveMapOrder() throws {
        let keys = ["zeta", "alpha", "mike", "bravo", "yankee", "charlie", "xray", "delta", "whiskey", "echo", "victor", "foxtrot"]
        let outputs = keys.map { "\"\($0)\": \"$response.body#/\($0)\"" }.joined(separator: ", ")
        let json = """
            {"arazzo": "1.1.0", "info": {"title": "t", "version": "1"},
             "sourceDescriptions": [{"name": "api", "url": "a.yaml", "type": "openapi"}],
             "workflows": [{"workflowId": "w", "steps": [{"stepId": "s", "operationId": "op", "outputs": {\(outputs)}}]}],
             "x-zz": 1, "x-aa": 2}
            """
        let document = try Arazzo.Document(json: Data(json.utf8))
        #expect(document.workflows[0].steps[0].outputs.keys == keys)
        #expect(document.vendorExtensions.keys == ["x-zz", "x-aa"])
        let reencoded = String(decoding: try document.jsonData(prettyPrinted: false), as: UTF8.self)
        let positions = keys.map { reencoded.range(of: "\"\($0)\"")!.lowerBound }
        #expect(positions == positions.sorted())
        #expect(try Arazzo.Document(json: document.jsonData()) == document)
        // Field order follows the specification tables.
        #expect(reencoded.hasPrefix(#"{"arazzo":"1.1.0","info":"#))
    }

    @Test func strictModeStillAppliesToJSON() {
        let json = #"{"arazzo": "1.1.0", "info": {"title": "t", "version": "1", "bogus": 1}, "sourceDescriptions": [], "workflows": []}"#
        #expect(throws: DecodingError.self) { try Arazzo.Document(json: Data(json.utf8), options: .init(strict: true)) }
        #expect(throws: DecodingError.self) { try Arazzo.Document(json: Data("{not json".utf8)) }
    }

    @Test func arazzo10GrammarIsLooser() throws {
        let yaml = """
            arazzo: 1.0.1
            info: {title: t, version: '1'}
            sourceDescriptions: [{name: api, url: a.yaml, type: openapi}]
            workflows:
              - workflowId: w
                steps:
                  - stepId: s
                    operationId: op
                    successCriteria:
                      - context: $response.body
                        condition: $.a
                        type: {type: jsonpath, version: rfc9535}
                    outputs:
                      weird: $components.inputs.pagination
            """
        let issues = try decodeYAML(Arazzo.Document.self, yaml).validate()
        #expect(issues.contains(rule: "runtime-expressions", path: "/workflows/0/steps/0/outputs/weird", severity: .warning))
        #expect(issues.contains(rule: "criteria", path: "/workflows/0/steps/0/successCriteria/0/type", severity: .warning))
        #expect(issues.errors.isEmpty, "\(issues.errors)")
    }
}
