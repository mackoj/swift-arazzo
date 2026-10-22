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

    @Test func jsonPathOnItsOwn() throws {
        let json = #"{"store": {"book": [{"title": "Sayings of the Century", "author": "Nigel Rees", "price": 8.95}, {"title": "Sword of Honour", "price": 12.99}, {"title": "Moby Dick", "price": 8.99}], "bicycle": {"price": 19.95}}}"#
        let document = try JSONValue(parsing: json)
        let path = try JSONPath("$.store.book[?@.price < 10].title")
        #expect(try path.values(in: document) == ["Sayings of the Century", "Moby Dick"])
        #expect(try path.paths(in: document).first?.description == "$['store']['book'][0]['title']")

        let jayway = try JSONPath("$.store.book[?(@.author =~ /.*REES/i)].price", dialect: .jayway)
        #expect(try jayway.values(in: document) == [.number(8.95)])
        let count = try JSONPath("$.store.book.length()", dialect: .jayway)
        #expect(try count.values(in: document) == [3])

        var mutable = document
        try mutable.replace(JSONPath("$..price"), with: 0)
        try mutable.remove(JSONPath("$.store.bicycle"))
        try mutable.map(JSONPath("$..title")) { .string($0.stringValue!.uppercased()) }
        try mutable.set("new", at: JSONPointer("/store/book/0/tag"))
        #expect(mutable["store"]?["book"]?[0] == ["title": "SAYINGS OF THE CENTURY", "author": "Nigel Rees", "price": 0, "tag": "new"])
        #expect(mutable["store"]?["bicycle"] == nil)
    }

    @Test func jsonPathCriterion() throws {
        var context = Arazzo.EvaluationContext()
        context.response = .init(body: ["pets": [["status": "available"]]])
        context.inputs = ["status": "available"]
        let criterion = Arazzo.Criterion(
            context: try .init("$response.body"), condition: "$.pets[?@.status == '{$inputs.status}']", type: .jsonPath)
        #expect(criterion.isSatisfied(in: context))
    }
}
