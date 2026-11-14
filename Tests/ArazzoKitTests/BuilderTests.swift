import ArazzoKit
import ArazzoKitBuilder
import Testing

@Suite("Result builder")
struct BuilderTests {
    @Test func buildsTheReadmeDocument() {
        // Given the README's "Building and encoding" document, written with memberwise initialisers
        let memberwise = Arazzo.Document(
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
                            onFailure: [.inline(.retry(name: "retry", after: 2, limit: 3))],
                            outputs: ["name": "$response.body#/name"]
                        )
                    ],
                    outputs: ["adoptedName": "$steps.getPet.outputs.name"]
                )
            ]
        )

        // When the same document is written with the builder
        let built = Arazzo.Document {
            Info(title: "Pets", version: "1.0.0")
            Source("petstore", url: "https://example.com/openapi.yaml", type: .openapi)
            Workflow("adopt") {
                Input("petId", schema: ["type": "integer"], required: true)
                Step("getPet", operationId: "getPetById") {
                    Parameter("petId", in: .path, value: "$inputs.petId")
                    SuccessCriterion("$statusCode == 200")
                    OnFailure.retry("retry", after: 2, limit: 3)
                    Output("name", "$response.body#/name")
                }
                Output("adoptedName", "$steps.getPet.outputs.name")
            }
        }

        // Then both are the same value
        #expect(built == memberwise)
    }

    @Test func buildsTheOfficialPetCouponsExample() throws {
        // Given the official pet-coupons example, decoded
        let decoded = try Fixtures.document("pet-coupons.arazzo.yaml")

        // When it is written with the builder
        let built = Arazzo.Document(arazzo: "1.0.0") {
            Info(
                title: "Petstore - Apply Coupons",
                description: """
                    Illustrates a workflow whereby a client a) finds a pet in the petstore,  b) finds coupons for that \
                    pet, and finally c) orders the pet while applying the coupons from step b.
                    """,
                version: "1.0.0")
            Source("pet-coupons", url: "./pet-coupons.openapi.yaml", type: .openapi)

            Workflow(
                "apply-coupon", summary: "Apply a coupon to a pet order.",
                description: """
                    This is how you can find a pet, find an applicable coupon, and apply that coupon in your order. \
                    The workflow concludes by outputting the ID of the placed order.
                    """
            ) {
                Step("find-pet", operationId: "findPetsByTags") {
                    Parameter("pet_tags", in: .query, value: "$inputs.my_pet_tags")
                    SuccessCriterion("$statusCode == 200")
                    Output("my_pet_id", "$response.body#/0/id")
                }
                .description("Find a pet based on the provided tags.")
                Step("find-coupons", operationId: "getPetCoupons") {
                    Parameter("pet_id", in: .path, value: "$steps.find-pet.outputs.my_pet_id")
                    SuccessCriterion("$statusCode == 200")
                    Output("my_coupon_code", "$response.body#/couponCode")
                }
                .description("Find a coupon available for the selected pet.")
                Step("place-order", workflowId: "place-order") {
                    Parameter("pet_id", value: "$steps.find-pet.outputs.my_pet_id")
                    Parameter("coupon_code", value: "$steps.find-coupons.outputs.my_coupon_code")
                    SuccessCriterion("$statusCode == 200")
                    Output("my_order_id", "$outputs.workflow_order_id")
                }
                .description("Place an order for the pet, applying the coupon.")
                Output("apply_coupon_pet_order_id", "$steps.place-order.outputs.my_order_id")
            }
            .inputs(.reference("#/components/inputs/apply_coupon_input"))

            Workflow(
                "buy-available-pet", summary: "Buy an available pet if one is available.",
                description: """
                    This workflow demonstrates a workflow very similar to `apply-coupon`, by intention. It's meant to \
                    indicate how to reuse a step (`place-order`) as well as a parameter (`page`, `pageSize`).
                    """
            ) {
                Step("find-pet", operationId: "findPetsByStatus") {
                    Parameter("status", in: .query, value: "available")
                    Parameter.reference("page", value: 1)
                    Parameter.reference("pageSize", value: 10)
                    SuccessCriterion("$statusCode == 200")
                    Output("my_pet_id", "$response.body#/0/id")
                }
                .description("Find a pet that is available for purchase.")
                Step("place-order", workflowId: "place-order") {
                    Parameter("pet_id", value: "$steps.find-pet.outputs.my_pet_id")
                    SuccessCriterion("$statusCode == 200")
                    Output("my_order_id", "$outputs.workflow_order_id")
                }
                .description("Place an order for the pet.")
                Output("buy_pet_order_id", "$steps.place-order.outputs.my_order_id")
            }
            .inputs(.reference("#/components/inputs/buy_available_pet_input"))

            Workflow(
                "place-order", summary: "Place an order for a pet.",
                description: """
                    This workflow places an order for a pet. It may be reused by other workflows as the "final step" \
                    in a purchase.
                    """
            ) {
                Input(
                    "pet_id",
                    schema: [
                        "type": "integer", "format": "int64", "description": "The ID of the pet to place in the order.",
                    ]
                )
                Input(
                    "quantity",
                    schema: [
                        "type": "integer", "format": "int32",
                        "description": "The number of pets to place in the order.",
                    ])
                Input(
                    "coupon_code", schema: ["type": "string", "description": "The coupon code to apply to the order."])
                Step("place-order", operationId: "placeOrder") {
                    RequestBody(
                        contentType: "application/json",
                        payload: [
                            "petId": "$inputs.pet_id", "quantity": "$inputs.quantity",
                            "couponCode": "$inputs.coupon_code", "status": "placed", "complete": false,
                        ])
                    SuccessCriterion("$statusCode == 200")
                    Output("step_order_id", "$response.body#/id")
                }
                .description("Place an order for the pet.")
                Output("workflow_order_id", "$steps.place-order.outputs.step_order_id")
            }

            Components {
                Input(
                    "apply_coupon_input",
                    schema: [
                        "type": "object",
                        "properties": [
                            "my_pet_tags": [
                                "type": "array", "items": ["type": "string"],
                                "description":
                                    "Desired tags to use when searching for a pet, in CSV format (e.g. \"puppy, dalmatian\")",
                            ],
                            "store_id": ["$ref": "#/components/inputs/store_id"],
                        ],
                    ])
                Input(
                    "buy_available_pet_input",
                    schema: ["type": "object", "properties": ["store_id": ["$ref": "#/components/inputs/store_id"]]])
                Input(
                    "store_id",
                    schema: [
                        "type": "string",
                        "description": """
                        Indicates the domain name of the store where the customer is browsing or buying pets, e.g. \
                        "pets.example.com" or "pets.example.co.uk".
                        """,
                    ])
                Parameter("page", in: .query, value: 1)
                Parameter("pageSize", in: .query, value: 100)
            }
        }

        // Then it is the decoded document
        #expect(built == decoded)
    }

    @Test func controlFlowShapesTheDocument() {
        // Given endpoints, one of them flaky, and a helper that returns a group of parameters
        let endpoints = [("list", "listPets", false), ("get", "getPet", true)]
        let paginated = true
        @StepBuilder func pagination() -> [any StepComponent] {
            Parameter.reference("page")
            Parameter.reference("pageSize")
        }

        // When steps come from a loop, actions from `if`, outputs from `switch` and parameters from the helper
        let document = Arazzo.Document {
            Workflow("smoke") {
                for (id, operationId, isFlaky) in endpoints {
                    Step(id, operationId: operationId) {
                        if paginated {
                            pagination()
                        }
                        SuccessCriterion("$statusCode == 200")
                        if isFlaky {
                            OnFailure.retry("retry", after: 1, limit: 3)
                        } else {
                            OnFailure.end("stop")
                        }
                        switch id {
                        case "get": Output("name", "$response.body#/name")
                        default: Output("count", "$response.body#/length")
                        }
                        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
                            Output("status", "$statusCode")
                        }
                    }
                }
            }
        }

        // Then each step reflects its own branch, in source order
        let steps = document.workflows[0].steps
        #expect(steps.map(\.stepId) == ["list", "get"])
        #expect(steps.map(\.parameters.count) == [2, 2])
        #expect(steps.map { $0.onFailure.first?.inlineValue?.kind.typeName } == ["end", "retry"])
        #expect(steps.map { Array($0.outputs.keys) } == [["count", "status"], ["name", "status"]])
    }

    @Test func successCriteriaStayAbsentUntilOneIsWritten() {
        // Given a step without criteria and one with a criterion
        // When both are built
        let without = Step("a", operationId: "a").step
        let with = Step("b", operationId: "b") { SuccessCriterion("$statusCode == 200") }.step

        // Then the first has no list at all and the second has one criterion
        #expect(without.successCriteria == nil)
        #expect(with.successCriteria == [.simple("$statusCode == 200")])
    }

    @Test func stepModifiersSetScalarFields() {
        // Given an AsyncAPI step with every modifier
        // When it is built
        let step = Step("listen", channelPath: "{$sourceDescriptions.events.url}#/channels/orders")
            .description("Wait for the order")
            .timeout(5_000)
            .dependsOn(["send"])
            .async(.receive, correlationId: "$message.header.id")
            .step

        // Then the scalars are set on the Step Object
        #expect(step.target == .channelPath("{$sourceDescriptions.events.url}#/channels/orders"))
        #expect(step.description == "Wait for the order")
        #expect(step.timeout == 5_000)
        #expect(step.dependsOn == ["send"])
        #expect(step.action == .receive)
        #expect(step.correlationId == "$message.header.id")
    }

    @Test func referencesBecomeReusableObjects() {
        // Given references to reusable components in a step
        // When it is built
        let step = Step("s", operationId: "op") {
            Parameter.reference("page", value: 2)
            OnSuccess.reference("done")
            OnFailure.reference("backoff")
        }
        .step

        // Then each is a Reusable Object of the right component type
        #expect(step.parameters == [.reusable(.init(.parameters, "page", value: 2))])
        #expect(step.onSuccess == [.reusable(.init(.successActions, "done"))])
        #expect(step.onFailure == [.reusable(.init(.failureActions, "backoff"))])
    }

    @Test func componentsAreKeyedByNameAndMerged() {
        // Given two Components blocks, a redefinition and a reference
        // When the document is built
        let document = Arazzo.Document {
            Components {
                Parameter("page", in: .query, value: 1)
                FailureAction.retry("backoff", after: 5, limit: 10)
            }
            Components {
                Parameter("page", in: .query, value: 2)
                Parameter.reference("ignored")
                SuccessAction.end("done")
            }
        }

        // Then definitions are keyed by name, the last one wins and the reference is not a definition
        #expect(Array(document.components.parameters.keys) == ["page"])
        #expect(document.components.parameters["page"]?.value == 2)
        #expect(document.components.failureActions["backoff"] == .retry(name: "backoff", after: 5, limit: 10))
        #expect(document.components.successActions["done"] == .end(name: "done"))
    }

    @Test func duplicateOutputsKeepTheLastValue() {
        // Given a step that declares the same output twice
        // When it is built
        let step = Step("s", operationId: "op") {
            Output("id", "$response.body#/id")
            Output("id", "$response.body#/uuid")
        }
        .step

        // Then the model holds one output, with the last value
        #expect(step.outputs == ["id": "$response.body#/uuid"])
    }

    @Test func modelInitialisersBuildTheSameDocument() {
        // Given the README document written with the top-level builder types
        let topLevel = Arazzo.Document {
            Info(title: "Pets", version: "1.0.0")
            Source("petstore", url: "https://example.com/openapi.yaml", type: .openapi)
            Workflow("adopt") {
                Input("petId", schema: ["type": "integer"], required: true)
                Step("getPet", operationId: "getPetById") {
                    Parameter("petId", in: .path, value: "$inputs.petId")
                    SuccessCriterion("$statusCode == 200")
                    OnFailure.retry("retry", after: 2, limit: 3)
                    Output("name", "$response.body#/name")
                }
                .description("Fetch the pet")
                Output("adoptedName", "$steps.getPet.outputs.name")
            }
        }

        // When it is written with the model types' initialisers and model values in the bodies
        let model = Arazzo.Document {
            Arazzo.Info(title: "Pets", version: "1.0.0")
            Arazzo.SourceDescription(name: "petstore", url: "https://example.com/openapi.yaml", type: .openapi)
            Arazzo.Workflow("adopt") {
                Input("petId", schema: ["type": "integer"], required: true)
                Arazzo.Step("getPet", target: .operationId("getPetById"), description: "Fetch the pet") {
                    Arazzo.Parameter(name: "petId", in: .path, value: "$inputs.petId")
                    Arazzo.Criterion.simple("$statusCode == 200")
                    Arazzo.FailureAction.retry(name: "retry", after: 2, limit: 3)
                    Output("name", "$response.body#/name")
                }
                Output("adoptedName", "$steps.getPet.outputs.name")
            }
        }

        // Then both are the same value
        #expect(model == topLevel)
    }

    @Test func modelInitialisersAreTheModelValues() {
        // Given scalar fields passed to the model initialisers
        // When a step and a workflow are built outside a document
        let step = Arazzo.Step(
            "listen", target: .channelPath("#/channels/orders"), timeout: 5_000, correlationId: "$message.header.id",
            action: .receive, dependsOn: ["send"]
        ) {
            Arazzo.RequestBody(contentType: "application/json")
        }
        let workflow = Arazzo.Workflow("orders", inputs: .reference("#/components/inputs/order"), dependsOn: ["auth"])

        // Then they are model values with those fields, and no steps or criteria they were not given
        #expect(step.timeout == 5_000)
        #expect(step.correlationId == "$message.header.id")
        #expect(step.action == .receive)
        #expect(step.dependsOn == ["send"])
        #expect(step.requestBody?.contentType == "application/json")
        #expect(step.successCriteria == nil)
        #expect(workflow.inputs == .reference("#/components/inputs/order"))
        #expect(workflow.dependsOn == ["auth"])
        #expect(workflow.steps.isEmpty)
    }

    @Test func typedReferencesWriteTheExpressions() {
        // Given a workflow whose step and output read an input and a step output through handles
        let typed = Arazzo.Document {
            Workflow("adopt") {
                let petId = Input("petId", schema: ["type": "integer"], required: true)
                petId
                let getPet = Step("getPet", operationId: "getPetById") {
                    Parameter("petId", in: .path, value: petId.expression)
                    Output("name", "$response.body#/name")
                }
                getPet
                Output("adoptedName", getPet.output("name"))
            }
            Workflow("report") {
                Arazzo.Step("adopt", target: .workflowId("adopt"))
                Output("name", Arazzo.Workflow("adopt").output("adoptedName"))
            }
        }

        // When the same document is written with expression strings
        let strings = Arazzo.Document {
            Workflow("adopt") {
                Input("petId", schema: ["type": "integer"], required: true)
                Step("getPet", operationId: "getPetById") {
                    Parameter("petId", in: .path, value: "$inputs.petId")
                    Output("name", "$response.body#/name")
                }
                Output("adoptedName", "$steps.getPet.outputs.name")
            }
            Workflow("report") {
                Step("adopt", workflowId: "adopt")
                Output("name", "$workflows.adopt.outputs.adoptedName")
            }
        }

        // Then the handles wrote the same expressions
        #expect(typed == strings)
    }

    @Test func componentKeysCanDifferFromNames() {
        // Given definitions whose component keys are not their names
        // When the Components Object is built
        let components = Arazzo.Components {
            Parameter("X-Trace-Id", in: .header, value: "telaio").componentKey("traceId")
            SuccessAction.end("done").componentKey("finish")
            FailureAction.retry("retry", limit: 3).componentKey("backoff")
            Arazzo.Parameter(name: "page", in: .query, value: 1)
        }

        // Then each is stored under its key, and a model value under its name
        #expect(Array(components.parameters.keys) == ["traceId", "page"])
        #expect(components.parameters["traceId"]?.name == "X-Trace-Id")
        #expect(components.successActions["finish"] == .end(name: "done"))
        #expect(components.failureActions["backoff"] == .retry(name: "retry", limit: 3))
    }

    @Test func builtDocumentsAreValidatedLikeDecodedOnes() {
        // Given a built workflow whose output references a step it does not have
        let document = Arazzo.Document {
            Info(title: "Pets", version: "1.0.0")
            Source("petstore", url: "./openapi.yaml", type: .openapi)
            Workflow("adopt") {
                Step("getPet", operationId: "getPetById") {
                    SuccessCriterion("$statusCode == 200")
                }
                Output("name", "$steps.findPet.outputs.name")
            }
        }

        // When it is validated
        let issues = document.validate()

        // Then validation reports it at the output's JSON Pointer
        #expect(issues.contains { $0.path == "/workflows/0/outputs/name" }, "\(issues)")
    }
}
