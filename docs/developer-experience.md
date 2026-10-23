# Developer experience: review and roadmap

2026-10-23

This review covers swift-arazzo 0.0.3 and its main consumer, [Telaio](https://github.com/mackoj/telaio), a macOS Arazzo editor. Every piece of code Telaio wrote to get around the library counts as evidence of a gap. Telaio paths are relative to that repository.

## Summary

swift-arazzo covers the specification well. It has typed, `Sendable` models for 1.0 and 1.1, an ABNF parser for runtime expressions, condition and JSONPath evaluation, and 18 validation rules, and the README examples are compiled by `ReadmeTests`. The friction starts after decoding. There are no tagged-release install instructions, no DocC articles, and no editing API, diagnostics carry no stable codes or source positions, and encoding drops data. So an editor like Telaio has had to build its own span index, source patcher, reference walker and lint layer. Most of the fixes below add API without breaking anything, and they would let consumers delete thousands of lines.

## Recommendations

Effort: S = a day or less, M = a few days, L = a week or more. "Breaking" means a source break for current callers.

### High

**H1. Install from a tagged version, and publish release notes.**
- *Problem:* the README tells users to depend on `branch: "main"`. A package that depends on a branch cannot itself be used by version, so this works for apps but not for libraries that build on swift-arazzo. The 0.0.2 release has no notes and there is no changelog, so consumers cannot tell what changed.
- *Evidence:* `README.md:40` and `README.md:57`. Telaio already uses `from: "0.0.2"` (`Packages/TelaioModel/Package.swift:18`), and its research notes still list "Tagged releases (`branch: "main"` only)" as missing (`docs/research/swift-arazzo.md`, §8).
- *Change:* use `from: "0.0.3"` in both snippets. Add a `CHANGELOG.md` (Added / Changed / Fixed, with a "Breaking" heading) and copy each section into the GitHub release. State the semver policy: before 1.0, a minor bump may break.
- *Effort:* S. *Breaking:* no.

**H2. Stable diagnostic codes, with message text that is not part of the contract.**
- *Problem:* `ValidationIssue.rule` names a whole rule family. `runtime-expressions` alone reports about ten different findings. Consumers who need to tell them apart match on `message`, so every wording fix is a breaking change for them.
- *Evidence:* `Sources/ArazzoKit/Validation/Validation.swift:4-31` (only `severity`, `path`, `message` and `rule`). Telaio's fixture tests match message text (`Packages/TelaioTestSupport/Tests/TelaioTestSupportTests/ArazzoFixtureTests.swift:82`, `"declares no output 'loanTransactionId'"`), which forces an `.upToNextMinor(from: "0.0.2")` pin (`Packages/TelaioTestSupport/Package.swift:21-22`).
- *Change:* add an `id` per finding and say that ids are stable and messages are not. List the ids in a DocC article.
  ```swift
  public struct ValidationIssue {
      public let code: Code            // e.g. "runtime-expressions.undeclared-output"
      public let rule: String          // unchanged
      public let specReference: String? // "Arazzo 1.1.0 §4.6.4"
  }
  ```
- *Effort:* M. *Breaking:* no (added fields; the memberwise `init` gets a defaulted `code`).

**H3. Lossless round trips for what the model already holds.**
- *Problem:* encoding drops or moves data that was decoded, which breaks the README's "lossless round trips" promise (CODING_STANDARDS.md).
- *Evidence:* `Reusable.encode` writes only `reference` and `value` (`Sources/ArazzoKit/Model/Reusable.swift:61`), so `x-*` keys are lost even in strict mode. `x-*` keys are always written after the fixed fields. Empty arrays are dropped by `encodeNonEmpty` (`Sources/ArazzoKit/Support/VendorExtensions.swift:100`), while `sourceDescriptions` and `workflows` are always written (`Sources/ArazzoKit/Model/Document.swift:68-69`). Telaio api-deltas #6, #7 and #8 list these, and `Writer/SourceWriter.swift` falls back to the canonical encoding when they get in the way.
- *Change:* make `Reusable` `VendorExtendable`. Record the source key order of each object, internally, and encode in that order (new objects keep the specification order). Keep an empty collection that was present in the source. Also keep unknown keys in lenient mode, in a `JSONValue` bag. Each of these gets a round-trip test that compares `jsonString`, not `==`.
- *Effort:* M. *Breaking:* no in the API; the encoded output changes, so it goes in the changelog.

**H4. Source locations for decoding errors and validation issues.**
- *Problem:* 0.0.3 added ranges inside expressions, but a `DecodingError` or a `ValidationIssue` cannot be placed in the file. Every editor, linter or CLI has to rebuild a pointer-to-text map on its own.
- *Evidence:* Telaio's `Packages/TelaioModel/Sources/TelaioModel/Source/SpanIndex.swift` (320 lines plus six test files) rebuilds spans from Yams start marks by following the rules in api-deltas §2.1. Research notes §3: "There is no line/column information."
- *Change:* add a public `SourceMap` to `ArazzoKitYAML` (for YAML) and to `ArazzoKit` (a span-tracking JSON scan), built while decoding:
  ```swift
  let (document, map) = try Arazzo.Document.decodeWithSourceMap(yaml: text)
  map.range(of: issue.path)          // Range<String.Index>?, key and value
  map.location(of: decodingError)    // line, column
  ```
  Telaio's SpanIndex, with its golden tests, is a ready starting point.
- *Effort:* L. *Breaking:* no.

### Medium

**M1. A DocC catalog with articles.**
- *Problem:* `.spi.yml` builds the reference docs, but there is no `.docc` catalog in `Sources/`, so there are no Getting Started, Validation or Editing articles and no list of diagnostic codes. The README is the only guide.
- *Change:* add `ArazzoKit.docc` with an overview, "Decoding and encoding", "Validating" (one table row per rule and code, with its severity and specification section), "Runtime expressions in an editor" and "Migrating between versions". Lift the README sections into it, and keep `ReadmeTests` as the compile check.
- *Effort:* M. *Breaking:* no.

**M2. An editing API: find and rename references.**
- *Problem:* renaming a step, workflow or source description safely means finding every `$steps.x`, `{$…}`, `dependsOn`, `goto` and component reference. Only the library knows all of those places.
- *Evidence:* Telaio's `Edit/ReferenceWalker.swift` (478 lines), `Edit/DocumentEdit.swift` (489 lines) and `Edit/DanglingReference.swift`.
- *Change:*
  ```swift
  document.references(to: .step(workflowId: "w", stepId: "login")) // [(pointer, range)]
  try document.rename(.step(workflowId: "w", stepId: "login"), to: "signIn")
  workflow.steps[id: "login"]?.description = "…"                   // keyed mutation
  ```
- *Effort:* L. *Breaking:* no.

**M3. Equality that tells documents apart.**
- *Problem:* `RuntimeExpression ==` compares only `kind` (`Sources/ArazzoKit/Expressions/RuntimeExpression.swift:153`), and `OrderedDictionary ==` ignores order. So `Document ==` does not see a reorder or a switch from dotted to pointer notation, and undo and dirty tracking built on `==` miss real edits.
- *Evidence:* Telaio's `Document/OrderedDictionary+Telaio.swift` (`isIdentical(to:)`, `renamingKey`) and api-deltas §2.3.
- *Change:* add `isIdentical(to:)` on `Document` and `JSONValue`, and an order-preserving `renamingKey(_:to:)` and `insert(_:at:)` on `OrderedDictionary` (in swift-jsonpath). Document the current meaning of `==` in DocC.
- *Effort:* S. *Breaking:* no.

**M4. Severity levels and rule metadata.**
- *Problem:* there are only two severities and no rule description, so consumers invent conventions.
- *Evidence:* Telaio D-20 (`docs/DECISIONS.md`) adds a third level through a `telaio/` name prefix (`Lint/TelaioLints.swift`). `BuiltInRules` is internal, so consumers can reach the built-in rules only by filtering `Validator.default.rules`.
- *Change:* add `Severity.info`. Give `ValidationRule` `summary` and `specReference`, and make `Validator.default.rules` the documented list. Let callers change a rule's severity (`.default.setting("output-names", to: .info)`).
- *Effort:* S. *Breaking:* adding a `Severity` case breaks exhaustive `switch`es; add it before 0.1.0.

**M5. Small ergonomics fixes found by Telaio's API smoke tests.**
- `Parameter.Identity` has no public init (api-deltas #2). Add one.
- `Criterion.ConditionType.stringValue` is `nil` for object-valued types (`Sources/ArazzoKit/Model/Criterion.swift:15`, api-deltas #3). Add `kind: ExpressionType.Kind`.
- `arazzo: 1.0` (a YAML number) fails decoding with a generic error (api-deltas #9). Accept it leniently with a warning, or explain it in the error.
- `DependencyCycleError` is nested in `Workflow`, where nobody looks for it (api-deltas #1). Mention it in the `executionOrder` doc comment.
- `init(contentsOf:)` takes `Data` while Foundation's initializer of the same name takes a URL. Rename it `init(sniffing:)` and deprecate the old name.
- *Effort:* S. *Breaking:* no, if the old names stay deprecated for one release.

### Low

**L1. A testing product for consumers.** `Tests/ArazzoKitTests/Support.swift` has useful internal helpers (`contains(rule:path:severity:)`, `errors`, `warnings`, fixture loading). Ship them as an `ArazzoKitTesting` library, together with the upstream example fixtures, so consumers stop copying them (Telaio has `TelaioTestSupport`). Effort M, not breaking.

**L2. An evaluation trace.** Explain why a criterion failed: which sub-condition, and the values resolved on each side. Telaio's research notes list this as missing. Effort M, not breaking.

**L3. Tooling.** Ship a small `arazzo` CLI (`validate`, `format`, `convert`) built on the library, with JSON and SARIF output for CI. Publish a JSON Schema file for editors. Effort M, not breaking.

**L4. Builders.** Add short constructors for common shapes (`.step("getPet", operationId: "getPetById") { … }`) once M2 settles how editing works. Effort M, not breaking.

## How the peers do it

- **OpenAPIKit** keeps one module per specification version (`OpenAPIKit30`, `OpenAPIKit`) and converts between them in `OpenAPIKitCompat`. It writes a migration guide for each major version. It collects non-fatal decoding findings in `document.warnings`, and `OpenAPI.Error` gives readable messages with a coding-path string. Its validation uses composable, typed `Validation` values. Its extensions are an unordered `[String: AnyCodable]`, so swift-arazzo's ordered maps are already better.
- **swift-openapi-runtime** publishes a DocC catalog, follows strict semver, deprecates with `@available(*, deprecated, renamed:)` for a release before removing anything, and runs API-breakage checks in CI, which swift-arazzo already does.
- **What to borrow:** a warnings list on decode, readable decoding-error messages, migration notes in DocC, and a deprecate-then-remove cycle. swift-arazzo's single model with a version field works well for 1.0 and 1.1, which differ little, so it should keep it rather than split into modules.

## Next three releases

| Release | Theme | Contents |
|---|---|---|
| **0.0.4** | Trust and docs | H1 (tagged install, changelog, semver policy), M3, M5, M1 (DocC catalog with a first article and the rule list) |
| **0.1.0** | Diagnostics | H2 (issue codes, spec references), M4 (`info` severity, rule metadata, severity overrides), the decode warnings list, L1 |
| **0.2.0** | Editors | H3 (lossless round trip), H4 (source map), M2 (references and rename), then L2 and L3 |

After 0.2.0, Telaio could delete `SpanIndex`, most of `ReferenceWalker`, the canonical fallback in `SourceWriter`, `OrderedDictionary+Telaio` and the `.upToNextMinor` pin. That would show the gaps are closed.
