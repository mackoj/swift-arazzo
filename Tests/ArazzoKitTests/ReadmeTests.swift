import ArazzoKit
import ArazzoKitYAML
import Foundation
import Testing

/// Keeps the README snippets compiling and truthful.
@Suite("README examples")
struct ReadmeTests {
    @Test func navigating() throws {
        let document = try Fixtures.document("pet-purchase-spec-example-1.1.arazzo.yaml")
        let workflow = try #require(document.workflow(id: "loginUserAndRetrievePet"))
        let step = try #require(workflow.step(id: "getPetStep"))

        var seen = ""
        switch step.target {
        case .operationId(let id): seen = "calls \(id)"
        case .operationPath(let path): seen = "calls \(path)"
        case .channelPath(let path): seen = "async channel \(path)"
        case .workflowId(let id): seen = "runs workflow \(id)"
        }
        #expect(seen.hasPrefix("calls {$sourceDescriptions"))

        guard case .path(let source, let pointer, _)? = step.target.operationReference else {
            Issue.record("expected an operation path")
            return
        }
        #expect(source == "petstoreDescription")
        #expect(pointer?.tokens == ["paths", "/pet/findByStatus", "get"])

        var names: [String] = []
        for case .inline(let parameter) in step.parameters { names.append(parameter.name) }
        #expect(names == ["status", "Authorization"])
    }

    @Test func expressionsAndEvaluation() throws {
        let expression = try Arazzo.RuntimeExpression("$steps.login.outputs.token#/access")
        #expect(expression.kind == .steps(stepId: "login", outputName: "token", pointer: JSONPointer(tokens: ["access"])))

        var context = Arazzo.EvaluationContext()
        context.statusCode = 200
        context.response = .init(headers: ["Content-Type": "application/json"], body: ["pets": [["id": 1]]])
        context.stepOutputs = ["login": ["token": "abc"]]
        context.inputs = ["host": "api.example.com"]

        #expect(try Arazzo.Condition("$statusCode == 200 && $response.body#/pets/0/id == 1").evaluate(in: context))

        let template = Arazzo.ExpressionTemplate("https://{$inputs.host}/pets/{$steps.login.outputs.token}")
        #expect(try template.render { try context.resolve($0) } == "https://api.example.com/pets/abc")
    }
}
