import ArazzoKit
import Testing

@Suite("Runtime expressions")
struct RuntimeExpressionTests {
    typealias Expr = Arazzo.RuntimeExpression

    @Test(
        "Parses every example from the specification table",
        arguments: [
            ("$method", Expr.Kind.method),
            ("$url", .url),
            ("$statusCode", .statusCode),
            ("$self", .self),
            ("$request.header.accept", .request(.header("accept"))),
            ("$request.path.id", .request(.path("id"))),
            ("$request.body#/user/uuid", .request(.body(JSONPointer(tokens: ["user", "uuid"])))),
            ("$response.body#/status", .response(.body(JSONPointer(tokens: ["status"])))),
            ("$response.body#/items/0/id", .response(.body(JSONPointer(tokens: ["items", "0", "id"])))),
            ("$response.body", .response(.body(nil))),
            ("$response.header.Server", .response(.header("Server"))),
            ("$response.header.X-Rate-Limit", .response(.header("X-Rate-Limit"))),
            ("$response.query.page size", .response(.query("page size"))),
            ("$message.header.Server", .message(.header("Server"))),
            ("$message.payload#/status", .message(.payload(JSONPointer(tokens: ["status"])))),
            ("$message.payload", .message(.payload(nil))),
            ("$inputs.username", .inputs(name: "username", pointer: nil)),
            ("$inputs.x-api-key", .inputs(name: "x-api-key", pointer: nil)),
            ("$inputs.productDetails.productId", .inputs(name: "productDetails.productId", pointer: nil)),
            ("$inputs.order#/items/0", .inputs(name: "order", pointer: JSONPointer(tokens: ["items", "0"]))),
            ("$outputs.bar", .outputs(name: "bar", pointer: nil)),
            ("$steps.someStepId.outputs.pets", .steps(stepId: "someStepId", outputName: "pets", pointer: nil)),
            (
                "$steps.someStepId.outputs.pets#/0/id",
                .steps(stepId: "someStepId", outputName: "pets", pointer: JSONPointer(tokens: ["0", "id"]))
            ),
            (
                "$workflows.foo.inputs.username",
                .workflows(workflowId: "foo", field: .inputs, name: "username", pointer: nil)
            ),
            (
                "$workflows.foo.outputs.mappedResponse#/name",
                .workflows(
                    workflowId: "foo", field: .outputs, name: "mappedResponse", pointer: JSONPointer(tokens: ["name"]))
            ),
            ("$sourceDescriptions.petstore.getPetById", .sourceDescriptions(name: "petstore", reference: "getPetById")),
            ("$sourceDescriptions.petstore.url", .sourceDescriptions(name: "petstore", reference: "url")),
            ("$components.parameters.foo", .components(type: .parameters, name: "foo")),
            ("$components.successActions.bar", .components(type: .successActions, name: "bar")),
            ("$components.failureActions.my.org.baz", .components(type: .failureActions, name: "my.org.baz")),
        ])
    func parses(_ text: String, _ kind: Expr.Kind) throws {
        let expression = try Expr(text)
        #expect(expression.kind == kind)
        #expect(expression.rawValue == text)
        #expect(expression.canonicalString == text)
        #expect(!expression.usesNonStandardNotation)
        // Rendering the structured form gives the same text back.
        #expect(Expr(kind).rawValue == text)
    }

    @Test(
        "Rejects invalid expressions",
        arguments: [
            "",
            "statusCode",
            "$status",
            "$steps.login.token",
            "$steps.log.in.outputs.token",
            "$workflows.foo.steps.bar",
            "$response.header.",
            "$response.header.bad header",
            "$response.cookie.session",
            "$response.body/items",
            "$response.body#items",
            "$response.body#/a~2b",
            "$inputs.",
            "$inputs.user name",
            "$components.inputs.pagination",
            "$components.parameters.",
            "$sourceDescriptions.petstore",
            "$sourceDescriptions.pet.store.x{y}",
            "$urlx",
            "{$inputs.id}",
        ])
    func rejects(_ text: String) {
        #expect(throws: Expr.ParseError.self) { try Expr(text) }
        let lenient = Expr(lenient: text)
        #expect(!lenient.isValid)
        #expect(lenient.rawValue == text)
    }

    @Test func acceptsDottedBodyPathsAsNonStandard() throws {
        let expression = try Expr("$response.body.items[0].id")
        #expect(expression.kind == .response(.body(JSONPointer(tokens: ["items", "0", "id"]))))
        #expect(expression.usesNonStandardNotation)
        #expect(expression.canonicalString == "$response.body#/items/0/id")
        #expect(try Expr("$message.payload.orderId").canonicalString == "$message.payload#/orderId")
    }

    @Test func accessors() throws {
        #expect(try Expr("$steps.a.outputs.b").referencedStepID == "a")
        #expect(try Expr("$sourceDescriptions.x.y").referencedSourceDescriptionName == "x")
        #expect(try Expr("$workflows.w.inputs.i").referencedWorkflowID == "w")
        #expect(try Expr("$inputs.i").referencedInputName == "i")
        #expect(try Expr("$response.body").isStepRuntimeOnly)
        #expect(try !Expr("$inputs.i").isStepRuntimeOnly)
    }

    @Test func jsonPointerEscapingRoundTrips() throws {
        let expression = try Expr("{$sourceDescriptions.petstore.url}".dropFirst().dropLast().description)
        #expect(expression.kind == .sourceDescriptions(name: "petstore", reference: "url"))
        let pointer = try JSONPointer("#/paths/~1pet~1findByStatus/get")
        #expect(pointer.tokens == ["paths", "/pet/findByStatus", "get"])
        #expect(pointer.description == "/paths/~1pet~1findByStatus/get")
        #expect(try JSONPointer("/a~0b").tokens == ["a~b"])
    }
}

@Suite("Expression templates")
struct ExpressionTemplateTests {
    @Test func splitsLiteralAndExpressions() {
        let template = Arazzo.ExpressionTemplate("https://{$inputs.host}/api/{$steps.create.outputs.id}/status")
        #expect(
            template.segments == [
                .literal("https://"),
                .expression(expression("$inputs.host")),
                .literal("/api/"),
                .expression(expression("$steps.create.outputs.id")),
                .literal("/status"),
            ])
        #expect(template.expressions.count == 2)
    }

    @Test func leavesJSONAndPathTemplatesAlone() {
        let json = Arazzo.ExpressionTemplate(#"{"petOrder": {"petId": "{$inputs.pet_id}", "path": "/pets/{petId}"}}"#)
        #expect(json.expressions == [expression("$inputs.pet_id")])
        #expect(json.invalidExpressions.isEmpty)
        #expect(Arazzo.ExpressionTemplate("no expressions {here}").segments == [.literal("no expressions {here}")])
    }

    @Test func reportsBrokenEmbeddedExpressions() {
        let template = Arazzo.ExpressionTemplate("Bearer {$steps.login.token}")
        #expect(template.expressions.isEmpty)
        #expect(template.invalidExpressions.map(\.text) == ["$steps.login.token"])
        #expect(template.segments == [.literal("Bearer {$steps.login.token}")])
    }

    @Test func rendersScalarsAndStructures() {
        let template = Arazzo.ExpressionTemplate(
            "id={$inputs.id}&tags={$inputs.tags}&flag={$inputs.flag}&none={$inputs.none}")
        let inputs: JSONValue = ["id": 42, "tags": ["a", "b"], "flag": true]
        let rendered = template.render { expression in
            guard case .inputs(let name, _) = expression.kind else { return nil }
            return inputs[name]
        }
        #expect(rendered == #"id=42&tags=["a","b"]&flag=true&none=null"#)
    }
}
