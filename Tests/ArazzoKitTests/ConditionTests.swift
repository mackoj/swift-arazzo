import ArazzoKit
import ArazzoKitYAML
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

    @Test(
        "Simple conditions",
        arguments: [
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

    @Test(
        "Rejects malformed conditions",
        arguments: [
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

    @Test func builtInJSONPathCriteria() throws {
        // Embedded expressions are substituted before the JSONPath is compiled.
        let named = Arazzo.Criterion(
            context: expression("$response.body"), condition: "$.pets[?@.name == '{$inputs.pattern}' || @.id == 1]",
            type: .jsonPath)
        #expect(try named.evaluate(in: Self.context))

        let none = Arazzo.Criterion(
            context: expression("$response.body"), condition: "$.pets[?@.id > 5]", type: .jsonPath)
        #expect(try !none.evaluate(in: Self.context))

        // RFC 9535 (the default) applies a filter to the members of the root object...
        let spec = "$[?count(@.pets) > 0]"
        #expect(
            try !Arazzo.Criterion(context: expression("$response.body"), condition: spec, type: .jsonPath).evaluate(
                in: Self.context))
        // ...while the Goessner draft version uses Jayway semantics and tests the root object itself.
        let goessner = Arazzo.Criterion(
            context: expression("$response.body"), condition: "$[?(@.pets.length() > 0)]",
            type: .expressionType(.init(kind: .jsonPath, version: .draftGoessnerDispatchJSONPath00)))
        #expect(try goessner.evaluate(in: Self.context))

        // Invalid JSONPath is an evaluation error, i.e. the criterion fails.
        let invalid = Arazzo.Criterion(context: expression("$response.body"), condition: "$[?", type: .jsonPath)
        #expect(throws: Arazzo.EvaluationError.self) { try invalid.evaluate(in: Self.context) }
        #expect(!invalid.isSatisfied(in: Self.context))

        // A body kept as JSON text is parsed before querying.
        let textual = Arazzo.EvaluationContext(response: .init(body: #"{"items": [1, 2]}"#))
        #expect(
            Arazzo.Criterion(context: expression("$response.body"), condition: "$.items[1]", type: .jsonPath)
                .isSatisfied(in: textual))
    }

    @Test func builtInSelectors() throws {
        func select(_ selector: String, _ type: Arazzo.SelectorType = .jsonPath) throws -> JSONValue? {
            try Arazzo.Selector(context: expression("$response.body"), selector: selector, type: type).evaluate(
                in: Self.context)
        }
        #expect(try select("$.pets[0].id") == 1)
        #expect(try select("$.pets[*].id") == [1, 2])  // several nodes → an array
        #expect(try select("$.nope") == nil)
        #expect(try select("/pets/1/name", .jsonPointer) == "Tom's")
        #expect(throws: Arazzo.EvaluationError.unsupportedQueryLanguage(.xPath)) { try select("/a", .xPath) }
    }

    @Test func selectorsSubstituteEmbeddedExpressions() throws {
        var context = Arazzo.EvaluationContext()
        context.response = .init(body: [
            ["country": "FR", "lang": "fr", "env_id": "fr-fr"],
            ["country": "BE", "lang": "fr", "env_id": "be-fr"],
            ["country": "BE", "lang": "nl", "env_id": "be-nl"],
        ])
        context.inputs = ["country": "BE", "lang": "fr", "index": 2]
        func select(_ selector: String, _ type: Arazzo.SelectorType = .jsonPath) throws -> JSONValue? {
            try Arazzo.Selector(context: expression("$response.body"), selector: selector, type: type)
                .evaluate(in: context)
        }
        #expect(try select("$[?@.lang == '{$inputs.lang}' && @.country == '{$inputs.country}'].env_id") == "be-fr")
        #expect(try select("$[{$inputs.index}].env_id") == "be-nl")
        let jayway = Arazzo.SelectorType.expressionType(
            .init(kind: .jsonPath, version: .draftGoessnerDispatchJSONPath00))
        #expect(
            try select("$.[?(@.lang == '{$inputs.lang}' && @.country == '{$inputs.country}')].env_id", jayway)
                == "be-fr")
        // A JSON Pointer is used as written.
        #expect(try select("/{$inputs.index}/env_id", .jsonPointer) == nil)

        let output = Arazzo.OutputValue.selector(
            .init(
                context: expression("$response.body"), selector: "$[?@.lang == '{$inputs.lang}'].env_id",
                type: .jsonPath))
        #expect(try output.evaluate(in: context) == ["fr-fr", "be-fr"])
        #expect(output.runtimeExpressions.map(\.rawValue) == ["$response.body", "$inputs.lang"])
    }

    @Test func customQueryEvaluators() throws {
        struct FakeXPath: Arazzo.QueryEvaluator {
            func supports(_ kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version) -> Bool {
                kind == .xPath
            }
            func evaluateCondition(
                _ condition: String, kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version,
                context: JSONValue
            ) throws -> Bool {
                condition == "/root/pets[name='available']" && version == .xpath31
            }
            func select(
                _ selector: String, kind: Arazzo.ExpressionType.Kind, version: Arazzo.ExpressionType.Version,
                context: JSONValue
            ) throws -> JSONValue? {
                "from-xpath"
            }
        }
        let xpath = Arazzo.Criterion(
            context: expression("$response.body"), condition: "/root/pets[name='{$inputs.expectedStatus}']",
            type: .xPath)
        #expect(throws: Arazzo.EvaluationError.self) { try xpath.evaluate(in: Self.context) }
        #expect(try xpath.evaluate(in: Self.context, queryEvaluator: FakeXPath()))
        // JSONPath keeps using the built-in engine when the evaluator does not support it.
        let jsonPath = Arazzo.Criterion(context: expression("$response.body"), condition: "$.pets[0]", type: .jsonPath)
        #expect(try jsonPath.evaluate(in: Self.context, queryEvaluator: FakeXPath()))
        let selector = Arazzo.Selector(context: expression("$response.body"), selector: "/a", type: .xPath)
        #expect(try selector.evaluate(in: Self.context, queryEvaluator: FakeXPath()) == "from-xpath")
    }

    @Test func payloadReplacements() throws {
        let body = try decodeYAML(
            Arazzo.RequestBody.self,
            """
            contentType: application/json
            payload:
              order:
                petId: 0
                quantity: 1
                note: "for {$steps.login.outputs.token}"
                items: [{sku: a, qty: 1}, {sku: b, qty: 1}]
            replacements:
              - target: /order/petId
                value: $response.body#/pets/1/id
              - target: $.order.items[?@.sku == 'b'].qty
                targetSelectorType: jsonpath
                value: 5
              - target: /order/tags
                value: [new]
            """)
        let payload = try body.resolvedPayload(in: Self.context)
        #expect(
            payload == [
                "order": [
                    "petId": 2, "quantity": 1, "note": "for abc",
                    "items": [["sku": "a", "qty": 1], ["sku": "b", "qty": 5]], "tags": ["new"],
                ]
            ])

        let template = Arazzo.RequestBody(
            contentType: "application/json", payload: #"{"token": "{$steps.login.outputs.token}", "n": 1}"#,
            replacements: [.init(target: "/n", value: 2)])
        #expect(try template.resolvedPayload(in: Self.context) == ["token": "abc", "n": 2])
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

        let value = Arazzo.Value.literal([
            "auth": "Bearer {$steps.login.outputs.token}", "count": "{$response.body#/count}",
        ])
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
