import LLMCheck
import Testing

/// The rules, run on the repository. A failure prints the rule, why it exists and how to fix it.
@Suite("Architecture rules")
struct ArchitectureRules {
    static func sources() throws -> Scope { try arazzo().productionCode.in("/Sources") }
    static func tests() throws -> Scope { try arazzo().testCode.in("/Tests") }

    @Test func libraryPerformsNoIO() throws {
        expectNone(Detect.impureCode(in: try Self.sources()), rule: .libraryPerformsNoIO)
    }

    @Test func foundationFallsBackFromEssentials() throws {
        expectNone(Detect.unguardedFoundationImports(in: try Self.sources()), rule: .foundationFallsBackFromEssentials)
    }

    @Test func importsStayWithinBudget() throws {
        let sources = try Self.sources()
        let found = Detect.importsOverBudget(
            arazzoKit: sources.in("Sources/ArazzoKit"), arazzoKitYAML: sources.in("Sources/ArazzoKitYAML"))
        expectNone(found, rule: .importsStayWithinBudget)
    }

    @Test func publicModelsAreHashableAndSendable() throws {
        let models = try Self.sources().in("Sources/ArazzoKit/Model")
        #expect(models.structs.count > 15)
        expectNone(Detect.publicTypesMissingConformances(in: models), rule: .publicModelsAreHashableAndSendable)
    }

    @Test func uncheckedSendableExplainsItself() throws {
        expectNone(Detect.uncommentedUncheckedSendable(in: try Self.sources()), rule: .uncheckedSendableExplainsItself)
    }

    @Test func testsUseSwiftTesting() throws {
        let tests = try Self.tests()
        #expect(tests.containing("import Testing").relativePaths.count > 5)
        expectNone(Detect.xcTestImports(in: tests), rule: .testsUseSwiftTesting)
    }

    @Test func knownIssuesExplainThemselves() throws {
        expectNone(Detect.unexplainedKnownIssues(in: try Self.tests()), rule: .knownIssuesExplainThemselves)
    }

    @Test func testsAreNotDisabled() throws {
        expectNone(Detect.disabledTests(in: try Self.tests()), rule: .testsAreNotDisabled)
    }

    @Test func tryLeadsExpectations() throws {
        let tests = try Self.tests()
        #expect(tests.containing("#expect").relativePaths.count > 5)
        expectNone(Detect.nestedTryInExpectations(in: tests), rule: .tryLeadsExpectations)
    }
}

/// Keeps `docs/architecture-rules.md` in step with the rules. Regenerate with
/// `LLM_CHECK_RECORD=1 swift test --package-path Architecture`.
@Test func rulesDocumentIsUpToDate() throws {
    let catalog = RuleCatalog(allRules)
    #expect(catalog.duplicateIDs.isEmpty)
    try expectFile(
        "docs/architecture-rules.md", in: arazzo(),
        matches: catalog.markdown(
            title: "Architecture rules",
            introduction: """
                The mechanical part of `CODING_STANDARDS.md` and `CONSTRAINTS.md`, enforced by the `Architecture/` \
                package with [swift-llm-check](https://github.com/mackoj/swift-llm-check): \
                `swift test --package-path Architecture` (macOS). Generated from its rules; do not edit by hand.
                """))
}
