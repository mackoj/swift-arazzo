import ArazzoKit
import ArazzoKitYAML
import Benchmark
import Foundation

/// The published examples the test suite decodes, read from `Tests/ArazzoKitTests/Fixtures` so there is one copy.
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tests/ArazzoKitTests/Fixtures")

    static let names = [
        "ExtendedParametersExample.arazzo.yaml", "FAPI-PAR.arazzo.yaml", "LoginAndRetrievePets.arazzo.yaml",
        "bnpl-arazzo.yaml", "oauth.arazzo.yaml", "pet-coupons.arazzo.yaml",
        "pet-purchase-spec-example-1.1.arazzo.yaml", "async-order-1.1.arazzo.yaml",
    ]

    static let yaml: [String] = names.map {
        try! String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)
    }

    static let documents: [Arazzo.Document] = yaml.map { try! Arazzo.Document(yaml: $0) }

    /// The bnpl example with its workflows repeated `copies` times under new IDs: a description far larger than the
    /// published ones, to show costs that grow with size.
    static func large(copies: Int = 50) -> Arazzo.Document {
        var document = try! Arazzo.Document(yaml: yaml[names.firstIndex(of: "bnpl-arazzo.yaml")!])
        let workflows = document.workflows
        document.workflows = (0..<copies).flatMap { copy in
            workflows.map { workflow in
                var workflow = workflow
                if copy > 0 { workflow.workflowId += "\(copy)" }
                return workflow
            }
        }
        return document
    }
}

let expressions = [
    "$url", "$method", "$statusCode", "$request.header.Authorization", "$request.query.page",
    "$request.body#/customer/id", "$response.body#/data/0/id", "$inputs.customer.firstName",
    "$steps.checkLoanCanBeProvided.outputs.eligibilityCheckRequired", "$workflows.apply.outputs.loanId",
    "$sourceDescriptions.BnplApi.url", "$components.parameters.page",
]

let conditions = [
    "$statusCode == 200",
    "$statusCode == 200 && $response.body#/pets/0/id == 1",
    "$response.header.Content-Type == 'application/json' || $statusCode >= 400",
    "!($inputs.count < 10) && $steps.login.outputs.token != null",
]

func evaluationContext() -> Arazzo.EvaluationContext {
    var context = Arazzo.EvaluationContext()
    context.statusCode = 200
    context.response = .init(
        headers: ["Content-Type": "application/json"],
        body: ["pets": .array((0..<50).map { ["id": .number(Double($0)), "status": "available"] })])
    context.inputs = ["count": 12, "host": "example.com", "status": "available"]
    context.stepOutputs = ["login": ["token": "abc"], "create": ["id": 42]]
    return context
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident, .retainCount],
        maxDuration: .seconds(2),
        maxIterations: 1_000
    )

    // MARK: Decoding and encoding

    Benchmark("Decode YAML, published examples") { benchmark in
        for text in Fixtures.yaml { blackHole(try Arazzo.Document(yaml: text)) }
    }

    let large = Fixtures.large()
    let largeJSON = try! large.jsonData(prettyPrinted: false)
    let largeYAML = try! large.yamlString()

    Benchmark("Decode JSON, large") { benchmark in
        blackHole(try Arazzo.Document(json: largeJSON))
    }

    Benchmark("Decode YAML, large") { benchmark in
        blackHole(try Arazzo.Document(yaml: largeYAML))
    }

    Benchmark("Decode JSON with JSONDecoder, large") { benchmark in
        blackHole(try JSONDecoder().decode(Arazzo.Document.self, from: largeJSON))
    }

    Benchmark("Encode JSON, large") { benchmark in
        blackHole(try large.jsonData(prettyPrinted: false))
    }

    Benchmark("Encode YAML, large") { benchmark in
        blackHole(try large.yamlString())
    }

    // MARK: Validation and resolution

    Benchmark("Validate, published examples") { benchmark in
        for document in Fixtures.documents { blackHole(document.validate()) }
    }

    Benchmark("Validate, large") { benchmark in
        blackHole(large.validate())
    }

    Benchmark("Execution order and effective parameters, large") { benchmark in
        for workflow in large.workflows {
            blackHole(try workflow.executionOrder(components: large.components))
            for step in workflow.steps { blackHole(try large.effectiveParameters(for: step, in: workflow)) }
        }
    }

    // MARK: Expressions

    Benchmark("Parse runtime expressions", configuration: .init(scalingFactor: .kilo)) { benchmark in
        for _ in benchmark.scaledIterations {
            for expression in expressions { blackHole(try Arazzo.RuntimeExpression(expression)) }
        }
    }

    Benchmark("Parse conditions", configuration: .init(scalingFactor: .kilo)) { benchmark in
        for _ in benchmark.scaledIterations {
            for condition in conditions { blackHole(try Arazzo.Condition(condition)) }
        }
    }

    let context = evaluationContext()
    let parsedConditions = conditions.map { try! Arazzo.Condition($0) }

    Benchmark("Evaluate conditions", configuration: .init(scalingFactor: .kilo)) { benchmark in
        for _ in benchmark.scaledIterations {
            for condition in parsedConditions { blackHole(try? condition.evaluate(in: context)) }
        }
    }

    let template = Arazzo.ExpressionTemplate("https://{$inputs.host}/pets/{$steps.create.outputs.id}?s={$statusCode}")

    Benchmark("Render expression template", configuration: .init(scalingFactor: .kilo)) { benchmark in
        for _ in benchmark.scaledIterations { blackHole(try template.render { try context.resolve($0) }) }
    }

    let criterion = Arazzo.Criterion(
        context: try! .init("$response.body"), condition: "$.pets[?@.status == '{$inputs.status}']", type: .jsonPath)

    Benchmark("Evaluate JSONPath criterion", configuration: .init(scalingFactor: .kilo)) { benchmark in
        for _ in benchmark.scaledIterations { blackHole(criterion.isSatisfied(in: context)) }
    }
}
