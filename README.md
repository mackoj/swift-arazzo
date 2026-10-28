# swift-arazzo

[![CI](https://github.com/mackoj/swift-arazzo/actions/workflows/ci.yml/badge.svg)](https://github.com/mackoj/swift-arazzo/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmackoj%2Fswift-arazzo%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mackoj/swift-arazzo)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmackoj%2Fswift-arazzo%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mackoj/swift-arazzo)

A Swift library for reading, writing, building and validating
[Arazzo](https://www.openapis.org/arazzo-specification) descriptions — the OpenAPI Initiative's
specification for describing sequences of API calls (workflows).

In the spirit of [OpenAPIKit](https://github.com/mattpolzin/OpenAPIKit): strongly-typed `Codable`
models for every object of the specification, with validation for the rules the type system
cannot express.

- **Arazzo 1.0.x and 1.1.x** — including 1.1's AsyncAPI steps (`channelPath`, `action`,
  `correlationId`, `timeout`, step `dependsOn`), Selector Objects, Expression Type Objects,
  `querystring` parameters and `$self`.
- **Linux first-class.** The core `ArazzoKit` module has **no third-party dependencies** and imports
  `FoundationEssentials` when available, so on Linux it links `libFoundationEssentials` only
  (no ICU payload). On Apple platforms it uses `Foundation`.
- **Swift 6**, strict concurrency, everything `Sendable` and `Hashable`.
- **Runtime expressions** parsed into a typed AST following the spec's ABNF, plus embedded
  `{$expression}` templates.
- **Simple conditions** (`$statusCode == 200 && $response.body#/id != null`) parsed and evaluated
  with the spec's comparison semantics; regex and **JSONPath** criteria evaluated natively; a plug-in
  point for XPath.
- **A complete JSONPath engine**, [swift-jsonpath](https://github.com/mackoj/swift-jsonpath) (pure Swift,
  no Foundation): RFC 9535 — passing all 715 cases of the official compliance test suite — and the
  Jayway dialect, passing the full Sextant / Jayway test suite. Used for `jsonpath` criteria,
  selectors and payload replacements, and re-exported by `ArazzoKit`.
- **Validation**: ~18 built-in rules (MUST → error, SHOULD → warning) reporting JSON Pointer paths,
  and an API for custom rules.
- **Resolution helpers**: reusable components, effective parameters/actions after workflow-level
  overrides, and a dependency-respecting step execution order.
- Optional **YAML** support (`ArazzoKitYAML`, built on [Yams](https://github.com/jpsim/Yams)) that
  preserves key order, behind the `YAML` package trait (enabled by default).

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mackoj/swift-arazzo.git", branch: "main"),
],
targets: [
    .target(name: "MyTool", dependencies: [
        .product(name: "ArazzoKit", package: "swift-arazzo"),
        .product(name: "ArazzoKitYAML", package: "swift-arazzo"), // optional
    ]),
]
```

Requires Swift 6.0+. Platforms: Linux, macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, visionOS 1+.

YAML support is the `YAML` [package trait](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packagetraits),
enabled by default. With Swift 6.1+, opt out to avoid building Yams; `ArazzoKitYAML` is then empty and
JSON remains available through `ArazzoKit`:

```swift
.package(url: "https://github.com/mackoj/swift-arazzo.git", branch: "main", traits: []),
```

Swift 6.0 has no package traits, so it always builds YAML support (`Package@swift-6.0.swift`).

| Product         | Depends on                         | Purpose                                  |
|-----------------|------------------------------------|------------------------------------------|
| `ArazzoKit`     | [swift-jsonpath](https://github.com/mackoj/swift-jsonpath), FoundationEssentials | Models, expressions, evaluation, validation |
| `ArazzoKitYAML` | `ArazzoKit`, Yams (`YAML` trait)   | YAML decoding/encoding                   |

## Usage

### Decoding

```swift
import ArazzoKit
import ArazzoKitYAML

let document = try Arazzo.Document(yaml: yamlString)          // YAML (or JSON) text
let document = try Arazzo.Document(json: data)                // JSON, no Yams needed
let document = try Arazzo.Document(contentsOf: data)          // sniffs JSON vs YAML

// Or with any Decoder:
let document = try JSONDecoder().decode(Arazzo.Document.self, from: data)
```

Decoding is **lenient by default**: unknown properties are ignored, fields that do not apply to an
action's `type` (such as `retryLimit` on a `goto`) are dropped, and runtime expressions that do not
parse are kept as `RuntimeExpression.Kind.invalid` so that one typo does not stop you from reading a
document — `validate()` reports them. Opt into **strict** decoding to reject unknown
properties, fields irrelevant to an action's `type`, and invalid expressions:

```swift
let document = try Arazzo.Document(yaml: yamlString, options: .init(strict: true))

// With your own decoder:
decoder.userInfo[Arazzo.DecodingOptions.key] = Arazzo.DecodingOptions(strict: true)
```

Structural problems (missing required fields, mutually exclusive `operationId`/`operationPath`/
`channelPath`/`workflowId`, a `goto` without target, unknown enum values) always fail decoding
with a `DecodingError` pointing at the offending coding path.

### Navigating

```swift
let workflow = document.workflow(id: "loginUserAndRetrievePet")!
let step = workflow.step(id: "getPetStep")!

switch step.target {
case .operationId(let id):    print("calls", id)
case .operationPath(let path): print("calls", path)
case .channelPath(let path):   print("async channel", path)
case .workflowId(let id):      print("runs workflow", id)
}

// Structured view of what the step targets:
if case .path(let source, let pointer, _)? = step.target.operationReference {
    print(source, pointer?.tokens ?? [])   // petstore ["paths", "/pet/findByStatus", "get"]
}

for case .inline(let parameter) in step.parameters {
    print(parameter.name, parameter.location?.rawValue ?? "-", parameter.value)
}

if case .selector(let selector)? = step.outputs["petId"] {
    print(selector.context, selector.selector, selector.type.kind)
}

document.info[extension: "x-owner"]      // specification extensions on every extensible object
```

Map-typed fields (`outputs`, `components.*`, JSON Schema properties, extensions) are
`OrderedDictionary`, so the document's key order survives JSON and YAML round trips
(`Arazzo.Document(json:)` / `jsonData()` use the order-preserving `JSONValueDecoder` / `JSONValueEncoder`;
Foundation's `JSONDecoder` does not expose keys in order). `Any`-typed fields
(payloads, literal values, extensions) are `JSONValue`. Workflow `inputs` are kept losslessly as
`Arazzo.JSONSchema` with accessors for `type`, `properties`, `required` and `$ref`.

### Building and encoding

```swift
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
                    onFailure: [.inline(.retry(name: "retry", after: 2, limit: 3))],
                    outputs: ["name": "$response.body#/name"]
                ),
            ],
            outputs: ["adoptedName": "$steps.getPet.outputs.name"]
        ),
    ]
)

let json = try document.jsonData(prettyPrinted: true)
let yaml = try document.yamlString()
```

### Validation

```swift
for issue in document.validate() {
    print(issue)   // [error] /workflows/0/steps/1/operationId: operationId references unknown source description 'petstoreDescription'. (step-targets)
}

try document.validateOrThrow()                       // throws Arazzo.ValidationError on errors
try document.validateOrThrow(failingOn: .warning)    // ...or on warnings too
```

Built-in rules include: unique `sourceDescriptions` names / `workflowId`s / `stepId`s (and their
recommended patterns), resolvable `operationId` / `operationPath` / `channelPath` / `workflowId`
targets (including the "qualify `operationId` when there are several sources" rule), workflow and
step `dependsOn` resolution and cycle detection, parameter `in` rules (required for operations,
forbidden in actions, no duplicates by `name`+`in`, `querystring` vs `query`), reusable
`$components` references of the right type, `goto`/`retry` targets, non-negative `retryAfter` /
`retryLimit` / `timeout`, criteria (`context` required with `type`, simple conditions parse, regexes
compile, Expression Type versions allowed), selector and payload-replacement checks, output and
component key patterns, `$ref` to `components.inputs`, and runtime-expression references (unknown
steps/outputs/inputs/workflows/sources/components, forward references in sequential workflows,
broken embedded `{$…}` expressions, non-ABNF dotted paths). Using 1.1 features in a document that
declares `arazzo: 1.0.x` produces warnings.

Custom rules:

```swift
let summaries = Arazzo.ValidationRule("workflow-summary") { document, report in
    for (index, workflow) in document.workflows.enumerated() where workflow.summary == nil {
        report.warning("/workflows/\(index)", "Every workflow should have a summary.")
    }
}
let issues = document.validate(using: .default.adding(summaries).removing("async-steps"))
```

### Runtime expressions

```swift
let expression = try Arazzo.RuntimeExpression("$steps.login.outputs.token#/access")
expression.kind   // .steps(stepId: "login", outputName: "token", pointer: /access)

let template = Arazzo.ExpressionTemplate("https://{$inputs.host}/pets/{$steps.create.outputs.id}")
template.expressions        // [$inputs.host, $steps.create.outputs.id]
try template.render { try context.resolve($0) }
```

Editors can highlight and diagnose expressions in place: `locatedSegments` pairs each segment with its
range in `rawValue`, and a `ParseError` carries the `range` of the offending text in its `expression`.

```swift
template.locatedSegments.map { template.rawValue[$0.range] }
// ["https://", "{$inputs.host}", "/pets/", "{$steps.create.outputs.id}"]

let error = Arazzo.RuntimeExpression(lenient: "$steps.login.token").parseError!
error.expression[error.range]   // ".token"
```

The parser follows the specification's ABNF. As a convenience (and because the specification's own
examples use it) dotted paths after `body`/`payload` are accepted —
`$response.body.data.id` ≡ `$response.body#/data/id` — and flagged by validation.

### Evaluating criteria

```swift
var context = Arazzo.EvaluationContext()
context.statusCode = 200
context.response = .init(headers: ["Content-Type": "application/json"], body: ["pets": [["id": 1]]])
context.stepOutputs = ["login": ["token": "abc"]]

try Arazzo.Condition("$statusCode == 200 && $response.body#/pets/0/id == 1").evaluate(in: context)  // true
step.successCriteria?.areSatisfied(in: context)
```

Simple conditions follow the specification: string comparisons are case-insensitive, numeric
strings are coerced for numeric comparisons, `null` only equals itself, and any evaluation error
makes the criterion fail (`isSatisfied`) — use `evaluate` to get the error. `regex` criteria are
evaluated with Swift `Regex`.

`jsonpath` criteria, Selector Objects and payload replacement targets use the built-in JSONPath
engine. The Expression Type version picks the dialect: `rfc9535` (the default) is strict RFC 9535;
`draft-goessner-dispatch-jsonpath-00` uses the Goessner-derived Jayway dialect (`[?(...)]`, `in`,
`=~`, `.length()`, ...). A selector matching several nodes yields an array of their values.

```swift
let criterion = Arazzo.Criterion(context: try .init("$response.body"),
                                 condition: "$.pets[?@.status == '{$inputs.status}']", type: .jsonPath)
criterion.isSatisfied(in: context)

let payload = try step.requestBody?.resolvedPayload(in: context)   // expressions, selectors and replacements applied
```

> **Note:** under RFC 9535 a filter applied to an object tests the object's *members*, so the
> specification's own example `$[?count(@.pets) > 0]` never matches `{"pets": [...]}` – write
> `$.pets[0]` (or use the Goessner version, where Jayway semantics test the object itself).

XPath needs a plug-in: conform to `Arazzo.QueryEvaluator` (returning `true` from `supports` only for
the languages you handle). `EvaluationContext` is a ready-made `RuntimeExpressionResolver`; conform
your own runtime to the protocol to evaluate against live state.

### JSONPath on its own

The engine lives in [swift-jsonpath](https://github.com/mackoj/swift-jsonpath) and is re-exported by
`ArazzoKit`, so `JSONValue`, `JSONPath`, `JSONPointer` and the Codable bridge are available directly:

```swift
import JSONPath

let document = try JSONValue(parsing: json)                    // order-preserving JSON parser
let path = try JSONPath("$.store.book[?@.price < 10].title")   // RFC 9535 (default)
try path.values(in: document)                                   // ["Sayings of the Century", "Moby Dick"]
try path.paths(in: document)                                    // [$['store']['book'][0]['title'], ...]

let jayway = try JSONPath("$.store.book[?(@.author =~ /.*REES/i)].price", dialect: .jayway)   // [8.95]
let count = try JSONPath("$.store.book.length()", dialect: .jayway)                         // [3]

var mutable = document
try mutable.replace(JSONPath("$..price"), with: 0)
try mutable.remove(JSONPath("$.store.bicycle"))
try mutable.map(JSONPath("$..title")) { .string($0.stringValue!.uppercased()) }
try mutable.set("new", at: JSONPointer("/store/book/0/tag"))
```

| Feature | `.rfc9535` | `.jayway` |
|---|---|---|
| Names, wildcards, indices, slices, unions, descendants | ✓ | ✓ |
| Filters | `[?expr]`, members of objects | `[?(expr)]` / `[?expr]`, the object itself |
| Comparisons | strict, typed | loose (`'1' == 1`), `===`, `!==` |
| Functions in filters | `length` `count` `match` `search` `value` | same, plus path functions |
| Jayway operators | – | `=~ /re/flags`, `in`, `nin`, `contains`, `all`, `size`, `empty`, `subsetof`, `anyof`, `noneof`, `type`, `exists` |
| Path functions | – | `length()` `size()` `avg()` `sum()` `min()` `max()` `stddev()` `concat()` `append()` `keys()` `first()` `last()` `index(n)` |
| Implicit `$` (`store.book`) | – | ✓ |

### Resolution

```swift
let parameters = try document.effectiveParameters(for: step, in: workflow)        // workflow params + step overrides, reusables resolved
let onSuccess  = try document.effectiveSuccessActions(for: step, in: workflow)
let onFailure  = try document.effectiveFailureActions(for: step, in: workflow)
let inputs     = try document.resolvedInputs(for: workflow)                       // follows #/components/inputs/…
let order      = try workflow.executionOrder(components: document.components)     // honours dependsOn + $steps references
```

## Specification coverage

| Arazzo object                     | Swift type                                        |
|-----------------------------------|---------------------------------------------------|
| Arazzo Specification Object       | `Arazzo.Document`                                 |
| Info Object                       | `Arazzo.Info`                                     |
| Source Description Object         | `Arazzo.SourceDescription`                        |
| Workflow Object                   | `Arazzo.Workflow`                                 |
| Step Object                       | `Arazzo.Step` (`Target`, `AsyncAction`)           |
| Parameter Object                  | `Arazzo.Parameter` (`Location`, `Arazzo.Value`)   |
| Success / Failure Action Object   | `Arazzo.SuccessAction` / `Arazzo.FailureAction`   |
| Components Object                 | `Arazzo.Components`                               |
| Reusable Object                   | `Arazzo.Reusable`, `Arazzo.ReusableOr<T>`         |
| Criterion Object                  | `Arazzo.Criterion` (`ConditionType`)              |
| (Criterion) Expression Type Object| `Arazzo.ExpressionType`, `Arazzo.SelectorType`    |
| Selector Object (1.1)             | `Arazzo.Selector`                                 |
| Request Body Object               | `Arazzo.RequestBody`                              |
| Payload Replacement Object        | `Arazzo.PayloadReplacement`                       |
| Runtime Expressions               | `Arazzo.RuntimeExpression`, `Arazzo.ExpressionTemplate` |
| JSON Schema (inputs)              | `Arazzo.JSONSchema`                               |
| Specification Extensions          | `VendorExtensions` on every extensible object     |

Out of scope (for now): fetching and parsing the referenced OpenAPI / AsyncAPI documents, executing
workflows, and an XPath engine.

## Development

```sh
swift build
swift test
```

The test suite decodes, round-trips and validates the examples published in
[OAI/Arazzo-Specification](https://github.com/OAI/Arazzo-Specification) (Apache-2.0) plus a 1.1
fixture covering every new feature. The JSONPath engine's own tests — the
[JSONPath Compliance Test Suite](https://github.com/jsonpath-standard/jsonpath-compliance-test-suite)
and the ported [Sextant](https://github.com/KittyMac/Sextant) suite — live in
[swift-jsonpath](https://github.com/mackoj/swift-jsonpath). Validation finds a few genuine mistakes in the upstream
examples (an expression missing `.outputs.` in `bnpl-arazzo.yaml`, a misspelled source description
in the 1.1.0 specification's root example); the tests assert they are reported.

CI runs on macOS and on Linux (Swift 6.0, 6.1 and 6.2). Pull requests also run the [swiftlang soundness checks](https://github.com/swiftlang/github-workflows) (swift-format, DocC, API breakage, YAML, shell, symlinks) and audit the workflows with actionlint and zizmor.
