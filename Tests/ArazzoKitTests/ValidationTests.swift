import ArazzoKit
import Testing

@Suite("Validation")
struct ValidationTests {
    typealias Step = Arazzo.Step

    static func step(
        _ id: String, _ target: Step.Target = .operationId("op"),
        parameters: [Arazzo.ReusableOr<Arazzo.Parameter>] = [],
        successCriteria: [Arazzo.Criterion]? = nil, onSuccess: [Arazzo.ReusableOr<Arazzo.SuccessAction>] = [],
        onFailure: [Arazzo.ReusableOr<Arazzo.FailureAction>] = [],
        outputs: OrderedDictionary<String, Arazzo.OutputValue> = [:], dependsOn: [String] = []
    ) -> Step {
        Step(
            stepId: id, target: target, parameters: parameters, successCriteria: successCriteria, onSuccess: onSuccess,
            onFailure: onFailure, outputs: outputs, dependsOn: dependsOn)
    }

    static func workflow(_ id: String = "wf", steps: [Step], dependsOn: [String] = []) -> Arazzo.Workflow {
        Arazzo.Workflow(workflowId: id, dependsOn: dependsOn, steps: steps)
    }

    @Test func requiredListsAndUniqueness() {
        let empty = makeDocument(sources: [], workflows: [])
        let issues = empty.validate()
        #expect(issues.contains(rule: "source-descriptions", path: "/sourceDescriptions", severity: .error))
        #expect(issues.contains(rule: "workflows", path: "/workflows", severity: .error))

        let duplicates = makeDocument(
            sources: [
                .init(name: "api", url: "a.yaml"), .init(name: "api", url: "b.yaml"),
                .init(name: "bad name", url: "c.yaml"),
            ],
            workflows: [
                Self.workflow("w", steps: [Self.step("s"), Self.step("s")]),
                Self.workflow("w", steps: []),
            ])
        let found = duplicates.validate()
        #expect(found.contains(rule: "source-descriptions", path: "/sourceDescriptions/1/name", severity: .error))
        #expect(found.contains(rule: "source-descriptions", path: "/sourceDescriptions/2/name", severity: .warning))
        #expect(found.contains(rule: "workflows", path: "/workflows/1/workflowId", severity: .error))
        #expect(found.contains(rule: "steps", path: "/workflows/0/steps/1/stepId", severity: .error))
        #expect(found.contains(rule: "steps", path: "/workflows/1/steps", severity: .error))
    }

    @Test func operationIdsMustBeQualifiedWithMultipleSources() {
        let document = makeDocument(
            sources: [
                .init(name: "a", url: "a.yaml", type: .openapi), .init(name: "b", url: "b.yaml", type: .openapi),
            ],
            workflows: [
                Self.workflow(steps: [
                    Self.step("plain", .operationId("getPet")),
                    Self.step("qualified", .operationId("$sourceDescriptions.a.getPet")),
                    Self.step("unknown", .operationId("$sourceDescriptions.zzz.getPet")),
                    Self.step("path", .operationPath("{$sourceDescriptions.b.url}#/paths/~1pets/get")),
                    Self.step("badPath", .operationPath("#/paths/~1pets/get")),
                ])
            ])
        let issues = document.validate()
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/0/operationId", severity: .error))
        #expect(!issues.contains(rule: "step-targets", path: "/workflows/0/steps/1/operationId"))
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/2/operationId", severity: .error))
        #expect(!issues.contains(rule: "step-targets", path: "/workflows/0/steps/3/operationPath"))
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/4/operationPath", severity: .error))
    }

    @Test func workflowReferences() {
        let document = makeDocument(
            sources: [
                .init(name: "api", url: "a.yaml", type: .openapi), .init(name: "flows", url: "f.yaml", type: .arazzo),
            ],
            workflows: [
                Self.workflow(
                    "a",
                    steps: [
                        Self.step("local", .workflowId("b")),
                        Self.step("missing", .workflowId("nope")),
                        Self.step("remote", .workflowId("$sourceDescriptions.flows.other")),
                        Self.step("wrongType", .workflowId("$sourceDescriptions.api.other")),
                    ], dependsOn: ["b"]),
                Self.workflow("b", steps: [Self.step("s")], dependsOn: ["a"]),
            ])
        let issues = document.validate()
        #expect(!issues.contains(rule: "step-targets", path: "/workflows/0/steps/0/workflowId"))
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/1/workflowId", severity: .error))
        #expect(!issues.contains(rule: "step-targets", path: "/workflows/0/steps/2/workflowId"))
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/3/workflowId", severity: .error))
        #expect(issues.contains { $0.rule == "workflow-dependencies" && $0.message.contains("cycle") })
    }

    @Test func parameterLocationRules() {
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step(
                        "op",
                        parameters: [
                            .inline(.init(name: "id", value: 1)),  // missing `in`
                            .inline(.init(name: "q", in: .query, value: 1)),
                            .inline(.init(name: "q", in: .query, value: 2)),  // duplicate
                            .inline(.init(name: "Auth", in: .header, value: 1)),
                            .inline(.init(name: "auth", in: .header, value: 2)),  // duplicate (case-insensitive header)
                            .inline(.init(name: "all", in: .querystring, value: "a=b")),
                        ]),
                    Self.step("sub", .workflowId("wf2"), parameters: [.inline(.init(name: "input", value: 1))]),
                    Self.step(
                        "act",
                        onSuccess: [
                            .inline(
                                .init(
                                    name: "go", kind: .goto(.workflow("wf2")),
                                    parameters: [.inline(.init(name: "x", in: .query, value: 1))]))
                        ]),
                ]),
                Self.workflow("wf2", steps: [Self.step("s")]),
            ])
        let issues = document.validate()
        #expect(issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/0/in", severity: .error))
        #expect(issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/2", severity: .error))
        #expect(issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/4", severity: .error))
        #expect(issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters", severity: .warning))
        #expect(!issues.contains(rule: "parameters", path: "/workflows/0/steps/1/parameters/0/in"))
        #expect(
            issues.contains(
                rule: "parameters", path: "/workflows/0/steps/2/onSuccess/0/parameters/0/in", severity: .error))
    }

    @Test func reusableReferences() {
        let components = Arazzo.Components(
            parameters: ["page": .init(name: "page", in: .query, value: 1)],
            successActions: ["done": .end(name: "done")],
            failureActions: ["jump": .goto(name: "jump", .step("elsewhere"))])
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step(
                        "s",
                        parameters: [
                            .reusable(.init(.parameters, "page", value: 2)),
                            .reusable(.init(.parameters, "missing")),
                            .reusable(.init(.successActions, "done")),
                        ],
                        onSuccess: [
                            .reusable(.init(.successActions, "done")), .reusable(.init(.failureActions, "jump")),
                        ],
                        onFailure: [.reusable(.init(.failureActions, "jump"))])
                ])
            ],
            components: components)
        let issues = document.validate()
        #expect(!issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/0/reference"))
        #expect(
            issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/1/reference", severity: .error))
        #expect(
            issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/2/reference", severity: .error))
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onSuccess/1/reference", severity: .error))
        // The reusable failure action targets a step that does not exist in this workflow.
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onFailure/0", severity: .error))
    }

    @Test func actionTargetsAndRetries() {
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step(
                        "a",
                        onSuccess: [
                            .inline(.goto(name: "next", .step("b"))), .inline(.goto(name: "next", .step("zzz"))),
                        ],
                        onFailure: [
                            .inline(.retry(name: "r", after: -1, limit: -2)),
                            .inline(.goto(name: "g", .workflow("nope"))),
                        ]),
                    Self.step("b"),
                ])
            ])
        let issues = document.validate()
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onSuccess/1/stepId", severity: .error))
        // duplicate name
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onSuccess/1", severity: .error))
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onFailure/0/retryAfter", severity: .error))
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onFailure/0/retryLimit", severity: .error))
        #expect(issues.contains(rule: "actions", path: "/workflows/0/steps/0/onFailure/1/workflowId", severity: .error))
    }

    @Test func criteriaRules() {
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step("empty", successCriteria: []),
                    Self.step(
                        "bad",
                        successCriteria: [
                            .init(condition: "$statusCode = 200"),
                            .init(condition: "$.a", type: .jsonPath),
                            .init(context: expression("$statusCode"), condition: "([", type: .regex),
                            .init(
                                context: expression("$response.body"), condition: "/a",
                                type: .expressionType(.init(kind: .xPath, version: "xpath-99"))),
                            .init(
                                context: expression("$response.body"), condition: "/a",
                                type: .expressionType(.init(kind: .jsonPointer, version: .rfc6901))),
                        ]),
                ])
            ])
        let issues = document.validate()
        #expect(issues.contains(rule: "steps", path: "/workflows/0/steps/0/successCriteria", severity: .error))
        let base = "/workflows/0/steps/1/successCriteria"
        #expect(issues.contains(rule: "criteria", path: "\(base)/0/condition", severity: .error))
        #expect(issues.contains(rule: "criteria", path: "\(base)/1/context", severity: .error))
        #expect(issues.contains(rule: "criteria", path: "\(base)/2/condition", severity: .error))
        #expect(issues.contains(rule: "criteria", path: "\(base)/3/type/version", severity: .error))
        #expect(issues.contains(rule: "criteria", path: "\(base)/4/type", severity: .error))
    }

    @Test func jsonPathSyntax() {
        let selector = Arazzo.Selector(context: expression("$response.body"), selector: "$.a[", type: .jsonPath)
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step(
                        "s",
                        successCriteria: [
                            .init(context: expression("$response.body"), condition: "$[?(@.a ==)]", type: .jsonPath),
                            .init(
                                context: expression("$response.body"), condition: "$.items.length()", type: .jsonPath),
                            .init(
                                context: expression("$response.body"), condition: "$.items.length()",
                                type: .expressionType(.init(kind: .jsonPath, version: .draftGoessnerDispatchJSONPath00))
                            ),
                            .init(
                                context: expression("$response.body"), condition: "$[?@.id == {$inputs.id}]",
                                type: .jsonPath),
                            .init(
                                context: expression("$response.body"), condition: "$[?count(@.pets) > 0]",
                                type: .jsonPath),
                        ],
                        outputs: ["bad": .selector(selector)])
                ])
            ])
        let issues = document.validate()
        let base = "/workflows/0/steps/0/successCriteria"
        #expect(issues.contains(rule: "criteria", path: "\(base)/0/condition", severity: .error))
        // Jayway path functions are not RFC 9535...
        #expect(issues.contains(rule: "criteria", path: "\(base)/1/condition", severity: .error))
        // ...but are fine with the Goessner draft version.
        #expect(!issues.contains(rule: "criteria", path: "\(base)/2/condition"))
        // Embedded runtime expressions are only known at runtime.
        #expect(!issues.contains(rule: "criteria", path: "\(base)/3/condition"))
        #expect(!issues.contains(rule: "criteria", path: "\(base)/4/condition"))
        #expect(issues.contains(rule: "selectors", path: "/workflows/0/steps/0/outputs/bad/selector", severity: .error))
    }

    @Test func runtimeExpressionReferences() {
        let document = makeDocument(
            workflows: [
                Arazzo.Workflow(
                    workflowId: "wf",
                    inputs: .object(properties: ["user": ["type": "string"]]),
                    steps: [
                        Self.step(
                            "first",
                            parameters: [
                                .inline(.init(name: "a", in: .query, value: "$steps.second.outputs.token")),  // forward
                                .inline(.init(name: "b", in: .query, value: "$steps.ghost.outputs.x")),  // unknown step
                                .inline(.init(name: "c", in: .query, value: "$inputs.pasword")),  // undeclared input
                                // broken template
                                .inline(.init(name: "d", in: .query, value: "Bearer {$steps.second.token}")),
                                .inline(.init(name: "e", in: .query, value: "$sourceDescriptions.nope.url")),
                                .inline(.init(name: "f", in: .query, value: "$response.body.id")),  // dotted
                            ]),
                        Self.step("second", outputs: ["token": "$response.body#/token"]),
                    ],
                    outputs: ["token": "$steps.second.outputs.missing", "code": "$statusCode"])
            ])
        let issues = document.validate()
        let base = "/workflows/0/steps/0/parameters"
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/0/value", severity: .error))
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/1/value", severity: .error))
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/2/value", severity: .warning))
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/3/value", severity: .warning))
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/4/value", severity: .error))
        #expect(issues.contains(rule: "runtime-expressions", path: "\(base)/5/value", severity: .warning))
        #expect(issues.contains(rule: "runtime-expressions", path: "/workflows/0/outputs/token", severity: .warning))
        #expect(issues.contains(rule: "runtime-expressions", path: "/workflows/0/outputs/code", severity: .warning))
    }

    @Test func forwardReferencesAreAllowedWithDependsOn() {
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step(
                        "first",
                        parameters: [.inline(.init(name: "a", in: .query, value: "$steps.second.outputs.token"))],
                        dependsOn: ["second"]),
                    Self.step("second", outputs: ["token": "$response.body#/token"]),
                ])
            ])
        #expect(document.validate().errors.isEmpty, "\(document.validate())")
    }

    @Test func stepDependencyCycles() {
        let document = makeDocument(
            workflows: [
                Self.workflow(steps: [
                    Self.step("a", dependsOn: ["b"]),
                    Self.step("b", dependsOn: ["a"]),
                    Self.step("c", dependsOn: ["c", "nope", "$workflows.wf.steps.a", "$workflows.wf.steps.zzz"]),
                ])
            ])
        let issues = document.validate()
        #expect(issues.contains { $0.rule == "step-dependencies" && $0.message.contains("cycle") })
        #expect(issues.contains(rule: "step-dependencies", path: "/workflows/0/steps/2/dependsOn/0", severity: .error))
        #expect(issues.contains(rule: "step-dependencies", path: "/workflows/0/steps/2/dependsOn/1", severity: .error))
        #expect(!issues.contains(rule: "step-dependencies", path: "/workflows/0/steps/2/dependsOn/2"))
        #expect(issues.contains(rule: "step-dependencies", path: "/workflows/0/steps/2/dependsOn/3", severity: .error))
    }

    @Test func oneOneFeaturesInAOneZeroDocumentAreFlagged() throws {
        var document = try Fixtures.document("async-order-1.1.arazzo.yaml")
        document.arazzo = .v1_0_1
        let issues = document.validate()
        #expect(issues.errors.isEmpty, "\(issues.errors)")
        #expect(issues.contains(rule: "self-uri", path: "/$self", severity: .warning))
        #expect(issues.contains(rule: "async-steps", path: "/workflows/0/steps/1", severity: .warning))
        #expect(issues.contains(rule: "parameters", path: "/workflows/0/steps/0/parameters/0/in", severity: .warning))
        #expect(issues.contains(rule: "selectors", path: "/workflows/0/steps/0/outputs/petId", severity: .warning))
    }

    @Test func selfURIAndNames() {
        var document = makeDocument(workflows: [
            Self.workflow(steps: [Self.step("s", outputs: ["bad key": "$statusCode"])])
        ])
        document.selfURI = "https://example.com/a.yaml#frag"
        document.components.parameters["bad/key"] = .init(name: "p", in: .query, value: 1)
        let issues = document.validate()
        #expect(issues.contains(rule: "self-uri", path: "/$self", severity: .error))
        #expect(issues.contains(rule: "output-names", path: "/workflows/0/steps/0/outputs/bad key", severity: .error))
        #expect(issues.contains(rule: "components", path: "/components/parameters/bad~1key", severity: .error))
    }

    @Test func inputsReferencesResolve() {
        let document = makeDocument(
            workflows: [
                Arazzo.Workflow(
                    workflowId: "wf", inputs: .reference("#/components/inputs/missing"), steps: [Self.step("s")])
            ])
        #expect(document.validate().contains(rule: "inputs", path: "/workflows/0/inputs/$ref", severity: .error))
    }

    @Test func customRulesAndThrowing() throws {
        let rule = Arazzo.ValidationRule("workflow-summary") { document, report in
            for (index, workflow) in document.workflows.enumerated() where workflow.summary == nil {
                report.warning("/workflows/\(index)", "Every workflow should have a summary.")
            }
        }
        let document = makeDocument(workflows: [Self.workflow(steps: [Self.step("s")])])
        #expect(document.validate().isEmpty)
        #expect(document.validate(using: .default.adding(rule)).contains(rule: "workflow-summary"))
        #expect(Arazzo.Validator.blank.adding(rule).rules.count == 1)
        try document.validateOrThrow(using: .default.adding(rule))  // warnings don't throw by default
        #expect(throws: Arazzo.ValidationError.self) {
            try document.validateOrThrow(using: .default.adding(rule), failingOn: .warning)
        }
        let withoutSteps = makeDocument(workflows: [Self.workflow(steps: [])])
        #expect(withoutSteps.validate(using: .default.removing("steps")).isEmpty)
    }
}
