import ArazzoKit
import Testing

@Suite("Resolution helpers")
struct ResolutionTests {
    @Test func effectiveParametersOverrideWorkflowParameters() throws {
        let components = Arazzo.Components(parameters: ["page": .init(name: "page", in: .query, value: 1)])
        let workflow = Arazzo.Workflow(
            workflowId: "wf",
            steps: [
                .init(
                    stepId: "s", target: .operationId("op"),
                    parameters: [
                        .inline(.init(name: "X-Token", in: .header, value: "override")),
                        .reusable(.init(.parameters, "page", value: 5)),
                        .inline(.init(name: "limit", in: .query, value: 10)),
                    ])
            ],
            parameters: [
                .inline(.init(name: "x-token", in: .header, value: "default")),
                .inline(.init(name: "page", in: .query, value: 0)),
                .inline(.init(name: "page", in: .path, value: 0)),
            ])
        let document = makeDocument(workflows: [workflow], components: components)
        let parameters = try document.effectiveParameters(for: workflow.steps[0], in: workflow)
        #expect(parameters.map(\.name) == ["X-Token", "page", "page", "limit"])
        #expect(parameters.map(\.value) == [.literal("override"), .literal(5), .literal(0), .literal(10)])
    }

    @Test func effectiveActionsMergeByName() throws {
        let components = Arazzo.Components(failureActions: ["retry": .retry(name: "retry", limit: 3)])
        let workflow = Arazzo.Workflow(
            workflowId: "wf",
            steps: [
                .init(
                    stepId: "s", target: .operationId("op"),
                    onSuccess: [.inline(.end(name: "finish"))],
                    onFailure: [.inline(.end(name: "retry"))])
            ],
            successActions: [.inline(.end(name: "finish")), .inline(.goto(name: "jump", .step("s")))],
            failureActions: [.reusable(.init(.failureActions, "retry")), .inline(.end(name: "abort"))])
        let document = makeDocument(workflows: [workflow], components: components)
        let success = try document.effectiveSuccessActions(for: workflow.steps[0], in: workflow)
        #expect(success.map(\.name) == ["finish", "jump"])
        let failure = try document.effectiveFailureActions(for: workflow.steps[0], in: workflow)
        #expect(failure.map(\.name) == ["retry", "abort"])
        #expect(failure[0].kind == .end)  // the step's definition wins

        #expect(throws: Arazzo.ResolutionError.self) {
            try components.resolve(Arazzo.ReusableOr<Arazzo.SuccessAction>.reusable(.init(.successActions, "nope")))
        }
    }

    @Test func executionOrderHonoursExplicitAndImplicitDependencies() throws {
        let workflow = Arazzo.Workflow(
            workflowId: "wf",
            steps: [
                .init(
                    stepId: "useToken", target: .operationId("a"),
                    parameters: [.inline(.init(name: "t", in: .header, value: "Bearer {$steps.login.outputs.token}"))]),
                .init(stepId: "confirm", target: .operationId("b"), dependsOn: ["$workflows.wf.steps.useToken"]),
                .init(stepId: "login", target: .operationId("c"), outputs: ["token": "$response.body#/token"]),
                .init(stepId: "independent", target: .operationId("d")),
            ])
        #expect(workflow.localDependencies(of: workflow.steps[0]) == ["login"])
        #expect(workflow.localDependencies(of: workflow.steps[1]) == ["useToken"])
        let order = try workflow.executionOrder().map(\.stepId)
        #expect(order == ["login", "useToken", "confirm", "independent"])
    }

    @Test func executionOrderDetectsCycles() {
        let workflow = Arazzo.Workflow(
            workflowId: "wf",
            steps: [
                .init(stepId: "a", target: .operationId("a"), dependsOn: ["b"]),
                .init(
                    stepId: "b", target: .operationId("b"),
                    successCriteria: [.simple("$steps.a.outputs.x == 1")]),
            ])
        #expect(throws: Arazzo.Workflow.DependencyCycleError.self) { try workflow.executionOrder() }
    }

    @Test func references() {
        #expect(Arazzo.WorkflowReference("login") == .local(workflowId: "login"))
        #expect(
            Arazzo.WorkflowReference("$sourceDescriptions.shared.login")
                == .sourceDescription(name: "shared", workflowId: "login"))
        #expect(Arazzo.WorkflowReference("$inputs.x") == nil)
        #expect(Arazzo.StepReference("a") == .local(stepId: "a"))
        #expect(Arazzo.StepReference("$workflows.w.steps.s") == .workflow(workflowId: "w", stepId: "s"))
        #expect(
            Arazzo.StepReference("$sourceDescriptions.n.w.steps.s")
                == .sourceDescription(name: "n", workflowId: "w", stepId: "s"))
        #expect(Arazzo.StepReference("$workflows.w.s") == nil)

        let path = Arazzo.Step.Target.operationPath("{$sourceDescriptions.petstore.url}#/paths/~1pet~1findByStatus/get")
        #expect(
            path.operationReference
                == .path(
                    sourceDescription: "petstore", pointer: JSONPointer(tokens: ["paths", "/pet/findByStatus", "get"]),
                    raw: "{$sourceDescriptions.petstore.url}#/paths/~1pet~1findByStatus/get"))
        #expect(Arazzo.Step.Target.operationId("getPet").operationReference == .operationId("getPet"))
    }
}
