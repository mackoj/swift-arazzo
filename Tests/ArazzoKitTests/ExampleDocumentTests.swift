import ArazzoKit
import ArazzoKitYAML
import Foundation
import Testing

@Suite("Official and spec example documents")
struct ExampleDocumentTests {
    @Test(
        "Decodes in strict mode",
        arguments: Fixtures.official10 + ["async-order-1.1.arazzo.yaml", "pet-purchase-spec-example-1.1.arazzo.yaml"])
    func decodesStrictly(_ name: String) throws {
        // bnpl contains an invalid runtime expression, which strict mode rejects at decode time.
        if name == "bnpl-arazzo.yaml" {
            #expect(throws: DecodingError.self) { try Fixtures.document(name, strict: true) }
        } else {
            _ = try Fixtures.document(name, strict: true)
        }
    }

    @Test("Round-trips through JSON", arguments: Fixtures.all)
    func jsonRoundTrip(_ name: String) throws {
        let document = try Fixtures.document(name)
        let data = try document.jsonData()
        let decoded = try Arazzo.Document(json: data)
        #expect(decoded == document)
    }

    @Test("Round-trips through YAML", arguments: Fixtures.all)
    func yamlRoundTrip(_ name: String) throws {
        let document = try Fixtures.document(name)
        let yaml = try document.yamlString()
        let decoded = try Arazzo.Document(yaml: yaml)
        #expect(decoded == document)
    }

    @Test(
        "Valid examples produce no validation errors",
        arguments: [
            "ExtendedParametersExample.arazzo.yaml",
            "FAPI-PAR.arazzo.yaml",
            "LoginAndRetrievePets.arazzo.yaml",
            "oauth.arazzo.yaml",
            "pet-coupons.arazzo.yaml",
            "async-order-1.1.arazzo.yaml",
        ])
    func validates(_ name: String) throws {
        let issues = try Fixtures.document(name).validate()
        #expect(issues.errors.isEmpty, "\(issues)")
    }

    @Test func richOneOneDocumentHasNoIssuesAtAll() throws {
        let issues = try Fixtures.document("async-order-1.1.arazzo.yaml").validate()
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func bnplExampleHasKnownMistakes() throws {
        let issues = try Fixtures.document("bnpl-arazzo.yaml").validate()
        // `$steps.retrieveFinalizedPaymentPlan.finalizedPaymentPlan` is missing `.outputs.`. Arazzo 1.0's
        // grammar technically allows it (`$steps.` followed by anything), so it is a warning for this 1.0 document.
        #expect(
            issues.contains(
                rule: "runtime-expressions", path: "/workflows/0/outputs/finalizedPaymentPlan", severity: .warning))
        // `initiateBnplTransaction` never declares a `loanTransactionId` output.
        #expect(issues.contains { $0.message.contains("declares no output 'loanTransactionId'") })
    }

    @Test func specExampleMisspelledSourceDescriptionIsCaught() throws {
        let issues = try Fixtures.document("pet-purchase-spec-example-1.1.arazzo.yaml").validate()
        // The 1.1.0 specification example refers to `petstoreDescription` but declares `petStoreDescription`.
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/0/operationId", severity: .error))
        #expect(issues.contains(rule: "step-targets", path: "/workflows/0/steps/1/operationPath", severity: .error))
        // ...and uses the non-ABNF `$message.payload.orderId`.
        #expect(issues.contains { $0.message.contains("$message.payload#/orderId") })
    }

    @Test func richDocumentModel() throws {
        let document = try Fixtures.document("async-order-1.1.arazzo.yaml")
        #expect(document.arazzo == .v1_1_0)
        #expect(document.selfURI == "https://api.example.com/workflows/async-order.arazzo.yaml")
        #expect(document.info[extension: "owner"] == "pets-team")
        #expect(document[extension: "x-generated-by"] == "swift-arazzo tests")
        #expect(document.sourceDescriptions.map(\.type) == [.openapi, .asyncapi, .arazzo])

        let workflow = try #require(document.workflow(id: "placeAsyncOrder"))
        #expect(workflow.inputs?.ref == "#/components/inputs/orderInputs")
        #expect(try document.resolvedInputs(for: workflow)?.required == ["correlationId", "quantity"])

        let findPets = try #require(workflow.step(id: "findPets"))
        #expect(findPets.target == .operationId("$sourceDescriptions.petStore.findPetsByStatus"))
        #expect(
            findPets.target.operationReference
                == .qualifiedOperationId(sourceDescription: "petStore", operationId: "findPetsByStatus"))
        #expect(findPets.outputs.keys == ["petId", "firstPetName", "allPets"])
        guard case .selector(let selector)? = findPets.outputs["petId"] else {
            Issue.record("expected a selector output")
            return
        }
        #expect(selector.type == .jsonPath)
        #expect(selector.context.kind == .response(.body(nil)))

        let criteria = try #require(findPets.successCriteria)
        #expect(criteria[1].type == .expressionType(.init(kind: .jsonPath, version: .rfc9535)))
        #expect(criteria[2].type == .regex)

        let placeOrder = try #require(workflow.step(id: "placeOrder"))
        #expect(placeOrder.action == .send)
        guard case .channelPath = placeOrder.target else {
            Issue.record("expected a channelPath target")
            return
        }
        #expect(placeOrder.requestBody?.replacements.count == 2)
        #expect(placeOrder.requestBody?.replacements[1].targetSelectorType?.kind == .jsonPath)

        let confirm = try #require(workflow.step(id: "confirmOrder"))
        #expect(confirm.timeout == 6000)
        #expect(confirm.action == .receive)
        #expect(confirm.dependsOn == ["placeOrder"])

        guard case .reusable(let reusable) = workflow.failureActions[0] else {
            Issue.record("expected a reusable failure action")
            return
        }
        #expect(reusable.component?.name == "retryLater")
        let retry = try document.components.resolve(workflow.failureActions[0])
        #expect(retry.kind == .retry(.init(retryAfter: 1.5, retryLimit: 3)))
    }

    @Test func yamlPreservesFieldOrder() throws {
        let document = try Fixtures.document("async-order-1.1.arazzo.yaml")
        let yaml = try document.yamlString()
        let arazzo = try #require(yaml.range(of: "arazzo:"))
        let info = try #require(yaml.range(of: "info:"))
        let workflows = try #require(yaml.range(of: "workflows:"))
        let components = try #require(yaml.range(of: "components:"))
        #expect(arazzo.lowerBound < info.lowerBound)
        #expect(info.lowerBound < workflows.lowerBound)
        #expect(workflows.lowerBound < components.lowerBound)
        // Output map order survives a round trip.
        let reparsed = try Arazzo.Document(yaml: yaml)
        #expect(reparsed.workflows[0].steps[0].outputs.keys == ["petId", "firstPetName", "allPets"])
    }

    @Test func detectsJSONVersusYAML() throws {
        let document = try Fixtures.document("oauth.arazzo.yaml")
        let fromJSON = try Arazzo.Document(contentsOf: try document.jsonData())
        let fromYAML = try Arazzo.Document(contentsOf: Data(try document.yamlString().utf8))
        #expect(fromJSON == document)
        #expect(fromYAML == document)
    }
}
