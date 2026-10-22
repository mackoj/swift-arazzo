import ArazzoKit
import Testing

@Suite("Conditions and criteria")
struct ConditionTests {
    static let context = Arazzo.EvaluationContext(
        url: "https://api.example.com/pets",
        method: "GET",
        statusCode: 200,
        response: .init(
            headers: ["Content-Type": "application/json", "X-Rate-Limit": "100"],
            body: [
                "count": 3,
                "status": "Available",
                "pets": [["id": 1, "name": "Rex"], ["id": 2, "name": "Tom's"]],
                "data": ["x": 1],
                "empty": nil,
            ]),
        inputs: ["threshold": 2, "expectedStatus": "available", "pattern": "Rex|Tom"],
        stepOutputs: ["login": ["token": "abc"]]
    )

    @Test("Simple conditions", arguments: [
        ("$statusCode == 200", true),
        ("$statusCode != 200", false),
        ("$statusCode == 200 && $response.body.data != null", true),
        ("$statusCode == 404 || $response.body#/count > $inputs.threshold", true),
        ("$response.body.count > $inputs.threshold", true),
        ("$response.body#/count >= 3 && $response.body#/count <= 3", true),
        ("$response.body#/count < 3", false),
        ("$response.body#/0 == null", true),
        ("$response.body#/empty == null", true),
        ("$response.body#/missing != null", false),
        ("null == null", true),
        ("$response.body#/status == 'available'", true),  // case-insensitive
        ("$response.body#/status == $inputs.expectedStatus", true),
        ("$response.header.x-rate-limit == 100", true),  // numeric string coercion, header case-insensitive
        ("$response.header.X-Rate-Limit > 99.5", true),
        ("$response.body#/pets/1/name == 'TOM''S'", true),  // escaped quote
        ("$response.body.pets[0].name == 'rex'", true),
        ("$response.body#/pets[1]['name'] == 'tom''s'", true),
        ("!($statusCode == 500)", true),
        ("!$response.body#/missing", true),
        ("($statusCode == 200 || $statusCode == 201) && $method == 'get'", true),
        ("$steps.login.outputs.token == 'ABC'", true),
        ("true", true),
        ("false || true && false", false),
        ("$response.body#/count", false),  // only `true` passes
        ("$response.body#/status > 5", false),
    ])
    func evaluates(_ condition: String, _ expected: Bool) throws {
        let parsed = try Arazzo.Condition(condition)
        #expect(try parsed.evaluate(in: Self.context) == expected, "\(parsed)")
    }

    @Test("Rejects malformed conditions", arguments: [
        "",
        "$statusCode = 200",
        "$statusCode == ",
        "$statusCode & 1",
        "($statusCode == 200",
        "$statusCode == 'unterminated",
        "$steps.login.token == 1",
        "status == 200",
    ])
    func rejects(_ condition: String) {
        #expect(throws: Arazzo.Condition.ParseError.self) { try Arazzo.Condition(condition) }
    }

    @Test func collectsRuntimeExpressions() throws {
        let condition = try Arazzo.Condition("$statusCode == 200 && $steps.a.outputs.b != $inputs.c")
        #expect(condition.runtimeExpressions.map(\.rawValue) == ["$statusCode", "$steps.a.outputs.b", "$inputs.c"])
    }

    @Test func regexCriteria() throws {
        let status = Arazzo.Criterion(context: expression("$statusCode"), condition: #"^2\d{2}$"#, type: .regex)
        #expect(status.isSatisfied(in: Self.context))
        let embedded = Arazzo.Criterion(
            context: expression("$response.body#/pets/0/name"), condition: "^({$inputs.pattern})$", type: .regex)
        #expect(try embedded.evaluate(in: Self.context))
        let missing = Arazzo.Criterion(context: expression("$response.body#/nope"), condition: ".*", type: .regex)
        #expect(!missing.isSatisfied(in: Self.context))
        let broken = Arazzo.Criterion(context: expression("$statusCode"), condition: "([", type: .regex)
        #expect(throws: Arazzo.EvaluationError.self) { try broken.evaluate(in: Self.context) }
        #expect(!broken.isSatisfied(in: Self.context))
    }

    @Test func queryLanguagesNeedAnEvaluator() throws {
        let criterion = Arazzo.Criterion(
            context: expression("$response.body"), condition: "$.pets[?(@.name == '{$inputs.expectedStatus}')]",
            type: .jsonPath)
        #expect(throws: Arazzo.EvaluationError.unsupportedQueryLanguage(.jsonPath)) {
            try criterion.evaluate(in: Self.context)
        }

        struct FakeJSONPath: Arazzo.QueryEvaluator {
            func evaluateCondition(
                _ condition: String, kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version,
                context: JSONValue
            ) throws -> Bool {
                // Embedded expressions are substituted before the query engine sees the condition.
                condition == "$.pets[?(@.name == 'available')]" && kind == .jsonPath && version == .rfc9535
                    && context["pets"] != nil
            }
            func select(
                _ selector: String, kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version,
                context: JSONValue
            ) throws -> JSONValue? {
                context["pets"]?[0]?["id"]
            }
        }
        #expect(try criterion.evaluate(in: Self.context, queryEvaluator: FakeJSONPath()))

        let selector = Arazzo.Selector(context: expression("$response.body"), selector: "$.pets[0].id", type: .jsonPath)
        #expect(try selector.evaluate(in: Self.context, queryEvaluator: FakeJSONPath()) == 1)
    }

    @Test func criteriaListsAreANDed() {
        let criteria: [Arazzo.Criterion] = [.simple("$statusCode == 200"), .simple("$response.body#/count == 3")]
        #expect(criteria.areSatisfied(in: Self.context))
        #expect(!(criteria + [.simple("$statusCode == 201")]).areSatisfied(in: Self.context))
        #expect(!([.simple("this is not valid")] as [Arazzo.Criterion]).areSatisfied(in: Self.context))
    }

    @Test func valuesAndSelectorsEvaluate() throws {
        let pointer = Arazzo.Selector(context: expression("$response.body"), selector: "/pets/1/id", type: .jsonPointer)
        #expect(try pointer.evaluate(in: Self.context) == 2)

        let value = Arazzo.Value.literal(["auth": "Bearer {$steps.login.outputs.token}", "count": "{$response.body#/count}"])
        #expect(try value.evaluate(in: Self.context) == ["auth": "Bearer abc", "count": 3])
        #expect(try Arazzo.Value("$statusCode").evaluate(in: Self.context) == 200)
    }

    @Test func contextResolvesDottedInputsAndDocumentFields() throws {
        let document = try Fixtures.document("async-order-1.1.arazzo.yaml")
        let context = Arazzo.EvaluationContext(inputs: ["productDetails": ["productId": "p-1"]], document: document)
        #expect(try context.resolve(expression("$inputs.productDetails.productId")) == "p-1")
        #expect(try context.resolve(expression("$sourceDescriptions.orders.url")) == "./orders.asyncapi.yaml")
        #expect(try context.resolve(expression("$self")) == .string(document.selfURI!))
        #expect(try context.resolve(expression("$components.parameters.storeId"))?["in"] == "header")
    }
}
