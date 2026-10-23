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

    @Test(
        "Parse errors carry the range of the offending text",
        arguments: [
            ("", ""),
            ("$urlx", "x"),
            ("$nope", "$nope"),
            ("$steps.login.token", ".token"),
            ("$steps..outputs.x", ".outputs.x"),
            ("$inputs.", ""),
            ("$inputs.id}", "}"),
            ("$inputs.x##/a", "#/a"),
            ("$response.body#/a~2b", "/a~2b"),
            ("$response.body.items[0", "[0"),
            ("$response.body.items['x].id", "['x]"),
            ("$response.body[0]x", "x"),
            ("$components.parameters.a b", "a b"),
            ("$steps.café.outputs.x", "é.outputs.x"),
            ("$response.header.Ünïcode", "Ünïcode"),
            ("$inputs.name#/pâté🐾{", "{"),
        ])
    func parseErrorRanges(_ text: String, _ offending: String) {
        do {
            _ = try Expr(text)
            Issue.record("'\(text)' parsed")
        } catch let error as Expr.ParseError {
            #expect(error.expression == text)
            #expect(String(text[error.range]) == offending)
            #expect(error.range.upperBound <= text.endIndex)
            #expect(Expr(lenient: text).parseError?.range == error.range)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func parseErrorRangesCountCharactersNotBytes() throws {
        let text = "$steps.café.outputs.x"
        let error = try #require(Expr(lenient: text).parseError)
        #expect(text.distance(from: text.startIndex, to: error.range.lowerBound) == 10)
        #expect(text.utf8.distance(from: text.startIndex, to: error.range.lowerBound) == 10)
        #expect(text.distance(from: text.startIndex, to: error.range.upperBound) == text.count)
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

    @Test func locatesLiteralAndExpressionSegments() {
        let template = Arazzo.ExpressionTemplate("https://{$inputs.host}/api/{$steps.create.outputs.id}/status")
        #expect(template.locatedSegments.map(\.segment) == template.segments)
        #expect(
            template.locatedSegments.map { String(template.rawValue[$0.range]) } == [
                "https://", "{$inputs.host}", "/api/", "{$steps.create.outputs.id}", "/status",
            ])
        expectContiguous(template)
    }

    @Test func locatesAdjacentExpressions() {
        let template = Arazzo.ExpressionTemplate("{$inputs.a}{$inputs.b}")
        #expect(template.segments == [.expression(expression("$inputs.a")), .expression(expression("$inputs.b"))])
        #expect(template.locatedSegments.map { String(template.rawValue[$0.range]) } == ["{$inputs.a}", "{$inputs.b}"])
        expectContiguous(template)
        #expect(Arazzo.ExpressionTemplate("").locatedSegments.isEmpty)
    }

    @Test func locatesExpressionsEmbeddedInJSON() {
        let template = Arazzo.ExpressionTemplate(#"{"petId": "{$inputs.pet_id}", "path": "/pets/{petId}"}"#)
        #expect(
            template.locatedSegments.map { String(template.rawValue[$0.range]) } == [
                #"{"petId": ""#, "{$inputs.pet_id}", #"", "path": "/pets/{petId}"}"#,
            ])
        expectContiguous(template)
    }

    @Test func locatesSegmentsInNonASCIIText() {
        let template = Arazzo.ExpressionTemplate("Pâté 🐶 → {$inputs.name} über {$response.body#/ñame/🐾}!")
        #expect(
            template.locatedSegments.map { String(template.rawValue[$0.range]) } == [
                "Pâté 🐶 → ", "{$inputs.name}", " über ", "{$response.body#/ñame/🐾}", "!",
            ])
        let starts = template.locatedSegments.map {
            template.rawValue.distance(from: template.rawValue.startIndex, to: $0.range.lowerBound)
        }
        #expect(starts == [0, 9, 23, 29, 53])
        expectContiguous(template)
    }

    @Test func locatesBrokenEmbeddedExpressions() throws {
        let template = Arazzo.ExpressionTemplate("Bearer {$steps.login.token}")
        let invalid = try #require(template.invalidExpressions.first)
        #expect(String(template.rawValue[invalid.range]) == "{$steps.login.token}")
        #expect(String(invalid.text[invalid.error.range]) == ".token")
        #expect(String(template.rawValue[invalid.errorRange]) == ".token")
        #expect(template.locatedSegments.map(\.range) == [template.rawValue.startIndex..<template.rawValue.endIndex])
    }

    @Test func locatesNestedBracesInNonASCIIText() throws {
        let template = Arazzo.ExpressionTemplate("ü {$steps.a.outputs.b{$inputs.c}} é")
        #expect(template.expressions.isEmpty)
        let invalid = try #require(template.invalidExpressions.first)
        #expect(String(template.rawValue[invalid.range]) == "{$steps.a.outputs.b{$inputs.c}")
        #expect(String(template.rawValue[invalid.errorRange]) == "{")
        #expect(template.rawValue.distance(from: template.rawValue.startIndex, to: invalid.errorRange.lowerBound) == 21)
        #expect(template.segments == [.literal("ü {$steps.a.outputs.b{$inputs.c}} é")])
        expectContiguous(template)
    }

    private func expectContiguous(_ template: Arazzo.ExpressionTemplate) {
        let ranges = template.locatedSegments.map(\.range)
        #expect(ranges.first?.lowerBound == template.rawValue.startIndex)
        #expect(ranges.last?.upperBound == template.rawValue.endIndex)
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
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
