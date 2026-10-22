import ArazzoKit
import ArazzoKitYAML
import Foundation
import Testing

@Suite("Decoding and encoding")
struct CodingTests {
    @Test func stepTargetsAreMutuallyExclusive() throws {
        let both = """
            stepId: s
            operationId: a
            workflowId: b
            """
        #expect(throws: DecodingError.self) { try decodeYAML(Arazzo.Step.self, both) }
        #expect(throws: DecodingError.self) { try decodeYAML(Arazzo.Step.self, "stepId: s") }
        let step = try decodeYAML(Arazzo.Step.self, "stepId: s\nchannelPath: '{$sourceDescriptions.a.url}#/channels/x'")
        #expect(step.target == .channelPath("{$sourceDescriptions.a.url}#/channels/x"))
    }

    @Test func successActions() throws {
        let goto = try decodeYAML(Arazzo.SuccessAction.self, "name: next\ntype: goto\nstepId: other")
        #expect(goto.kind == .goto(.step("other")))
        let end = try decodeYAML(Arazzo.SuccessAction.self, "name: done\ntype: end")
        #expect(end.kind == .end)
        #expect(throws: DecodingError.self) { try decodeYAML(Arazzo.SuccessAction.self, "name: x\ntype: goto") }
        #expect(throws: DecodingError.self) {
            try decodeYAML(Arazzo.SuccessAction.self, "name: x\ntype: goto\nstepId: a\nworkflowId: b")
        }
        #expect(throws: DecodingError.self) { try decodeYAML(Arazzo.SuccessAction.self, "name: x\ntype: retry") }
        // Irrelevant fields are tolerated by default and rejected in strict mode.
        _ = try decodeYAML(Arazzo.SuccessAction.self, "name: done\ntype: end\nstepId: a")
        #expect(throws: DecodingError.self) {
            try decodeYAML(Arazzo.SuccessAction.self, "name: done\ntype: end\nstepId: a", strict: true)
        }
    }

    @Test func failureActions() throws {
        let retry = try decodeYAML(
            Arazzo.FailureAction.self, "name: r\ntype: retry\nretryAfter: 1\nretryLimit: 5\nworkflowId: refresh")
        #expect(retry.kind == .retry(.init(retryAfter: 1, retryLimit: 5, target: .workflow("refresh"))))
        #expect(retry.target == .workflow("refresh"))
        let bare = try decodeYAML(Arazzo.FailureAction.self, "name: r\ntype: retry")
        guard case .retry(let details) = bare.kind else {
            Issue.record("expected retry")
            return
        }
        #expect(details.effectiveRetryLimit == 1)
        #expect(throws: DecodingError.self) {
            try decodeYAML(Arazzo.FailureAction.self, "name: g\ntype: goto\nretryLimit: 2\nstepId: a", strict: true)
        }
        // Encoding writes the type and only the relevant fields.
        let json = String(decoding: try JSONEncoder().encode(retry), as: UTF8.self)
        #expect(json.contains(#""type":"retry""#))
        #expect(json.contains(#""retryLimit":5"#))
    }

    @Test func strictModeRejectsUnknownFields() throws {
        let yaml = """
            title: T
            version: 1.0.0
            x-ok: true
            colour: blue
            """
        let info = try decodeYAML(Arazzo.Info.self, yaml)
        #expect(info.vendorExtensions == ["x-ok": true])
        #expect(throws: DecodingError.self) { try decodeYAML(Arazzo.Info.self, yaml, strict: true) }
    }

    @Test func reusableObjectsIgnoreExtraProperties() throws {
        let yaml = "reference: $components.parameters.page\nvalue: 1\nx-extra: ignored"
        let parameter = try decodeYAML(Arazzo.ReusableOr<Arazzo.Parameter>.self, yaml, strict: true)
        #expect(parameter == .reusable(.init(.parameters, "page", value: 1)))
    }

    @Test func parameterValues() throws {
        let expressionParameter = try decodeYAML(Arazzo.Parameter.self, "name: a\nin: query\nvalue: $inputs.a")
        #expect(expressionParameter.value == .expression(expression("$inputs.a")))

        let literal = try decodeYAML(Arazzo.Parameter.self, "name: a\nin: header\nvalue: 'Bearer {$inputs.token}'")
        #expect(literal.value == .literal("Bearer {$inputs.token}"))
        #expect(literal.value.template?.expressions == [expression("$inputs.token")])

        let dollars = try decodeYAML(Arazzo.Parameter.self, "name: price\nin: query\nvalue: $5")
        #expect(dollars.value == .literal("$5"))

        let number = try decodeYAML(Arazzo.Parameter.self, "name: limit\nin: query\nvalue: 10")
        #expect(number.value == .literal(10))

        let quotedNumber = try decodeYAML(Arazzo.Parameter.self, "name: limit\nin: query\nvalue: '10'")
        #expect(quotedNumber.value == .literal("10"))

        let selector = try decodeYAML(
            Arazzo.Parameter.self,
            """
            name: id
            in: path
            value:
              context: $steps.a.outputs.xml
              selector: /Invoice/Id
              type:
                type: xpath
                version: xpath-30
            """)
        #expect(
            selector.value
                == .selector(
                    .init(
                        context: expression("$steps.a.outputs.xml"), selector: "/Invoice/Id",
                        type: .expressionType(.init(kind: .xPath, version: .xpath30)))))

        // An object that only looks a bit like a selector stays a literal.
        let object = try decodeYAML(Arazzo.Parameter.self, "name: f\nin: query\nvalue:\n  context: nope\n  other: 1")
        #expect(object.value == .literal(["context": "nope", "other": 1]))

        #expect(throws: DecodingError.self) {
            try decodeYAML(Arazzo.Parameter.self, "name: a\nin: body\nvalue: 1")
        }
    }

    @Test func criterionTypes() throws {
        let simple = try decodeYAML(Arazzo.Criterion.self, "condition: $statusCode == 200")
        #expect(simple.type == nil)
        #expect(simple.effectiveType == .simple)
        let typed = try decodeYAML(
            Arazzo.Criterion.self,
            "context: $response.body\ncondition: $.a\ntype:\n  type: jsonpath\n  version: draft-goessner-dispatch-jsonpath-00")
        #expect(typed.type == .expressionType(.init(kind: .jsonPath, version: .draftGoessnerDispatchJSONPath00)))
        #expect(throws: DecodingError.self) {
            try decodeYAML(Arazzo.Criterion.self, "condition: x\ntype: sql")
        }
    }

    @Test func requestBodyPayloadsKeepTheirShape() throws {
        let body = try decodeYAML(
            Arazzo.RequestBody.self,
            """
            contentType: application/json
            payload:
              petOrder:
                petId: $inputs.pet_id
                quantity: 1
                complete: false
                note: null
            replacements:
              - target: /petOrder/quantity
                value: $inputs.quantity
            """)
        #expect(body.isJSON)
        #expect(body.payload?["petOrder"]?["complete"] == false)
        #expect(body.payload?["petOrder"]?["note"] == .null)
        #expect(body.runtimeExpressions.map(\.rawValue) == ["$inputs.pet_id", "$inputs.quantity"])
        #expect(body.replacements[0].effectiveTargetKind(in: body) == .jsonPointer)

        let xml = try decodeYAML(Arazzo.RequestBody.self, "contentType: application/xml\npayload: '<a>{$inputs.x}</a>'")
        #expect(xml.isXML)
        #expect(xml.runtimeExpressions == [expression("$inputs.x")])
    }

    @Test func versionsAreLenientAboutYAMLNumbers() throws {
        let info = try decodeYAML(Arazzo.Info.self, "title: T\nversion: 1.0")
        #expect(info.version == "1.0")
        let version = try decodeYAML(Arazzo.SpecificationVersion.self, "1.0.1")
        #expect(version == .v1_0_1)
        #expect(version.isSupported)
        #expect(!version.supportsV1_1Features)
        #expect(Arazzo.SpecificationVersion(rawValue: "2.0.0")?.isSupported == false)
        #expect(Arazzo.SpecificationVersion(rawValue: "1.1") == nil)
        #expect(Arazzo.SpecificationVersion.v1_0_0 < .v1_1_0)
    }

    @Test func buildsDocumentsInCode() throws {
        let document = Arazzo.Document(
            info: .init(title: "Pets", version: "1.0.0"),
            sourceDescriptions: [.init(name: "petstore", url: "https://example.com/openapi.yaml", type: .openapi)],
            workflows: [
                .init(
                    workflowId: "adopt",
                    inputs: .object(properties: ["petId": ["type": "integer"]], required: ["petId"]),
                    steps: [
                        .init(
                            stepId: "getPet",
                            target: .operationId("getPetById"),
                            parameters: [.inline(.init(name: "petId", in: .path, value: "$inputs.petId"))],
                            successCriteria: [.simple("$statusCode == 200")],
                            outputs: ["name": "$response.body#/name"]
                        ),
                        .init(
                            stepId: "adopt",
                            target: .operationId("adoptPet"),
                            parameters: [.inline(.init(name: "petId", in: .path, value: "$inputs.petId"))],
                            requestBody: .init(contentType: "application/json", payload: ["name": "$steps.getPet.outputs.name"]),
                            onFailure: [.inline(.retry(name: "retry", after: 2, limit: 3))]
                        ),
                    ],
                    outputs: ["adoptedName": "$steps.getPet.outputs.name"]
                )
            ]
        )
        #expect(document.validate().isEmpty, "\(document.validate())")
        let yaml = try document.yamlString()
        #expect(yaml.contains("arazzo: 1.1.0"))
        #expect(try Arazzo.Document(yaml: yaml) == document)
    }

    @Test func orderedDictionaryBasics() {
        var dictionary: OrderedDictionary<String, Int> = ["b": 2, "a": 1]
        dictionary["c"] = 3
        dictionary["b"] = 20
        #expect(dictionary.keys == ["b", "a", "c"])
        #expect(dictionary.values == [20, 1, 3])
        dictionary["a"] = nil
        #expect(dictionary.keys == ["b", "c"])
        #expect(dictionary == ["c": 3, "b": 20])  // order-insensitive equality
        #expect(dictionary.map(\.key) == ["b", "c"])
    }

    @Test func jsonValueSerialization() throws {
        let value: JSONValue = ["s": "quote\" and \\ and \n", "n": 1.5, "i": 2, "b": true, "z": nil, "a": [1, "x"]]
        #expect(value.jsonString == #"{"s":"quote\" and \\ and \n","n":1.5,"i":2,"b":true,"z":null,"a":[1,"x"]}"#)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(value.jsonString.utf8))
        #expect(decoded == value)
    }
}
