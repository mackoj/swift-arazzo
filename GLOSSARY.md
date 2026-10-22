# swift-arazzo

Swift models, runtime expressions, condition evaluation and validation for Arazzo descriptions, and the JSONPath engine they use. Terms follow the [Arazzo Specification](https://spec.openapis.org/arazzo/latest.html) and [RFC 9535](https://www.rfc-editor.org/rfc/rfc9535); the Swift type is in parentheses.

## Documents

**Specification**:
The Arazzo Specification itself, published by the OpenAPI Initiative. Its `major.minor` decides the feature set; patch versions are clarifications.
_Avoid_: spec (when it could mean a Document or an OpenAPI description)

**Specification version** (`Arazzo.SpecificationVersion`):
The `arazzo` field of a Document. Using 1.1 features under a 1.0.x version is a warning, not an error.
_Avoid_: document version (that is `info.version`)

**Document** (`Arazzo.Document`):
One Arazzo description: the root object holding Info, Source descriptions, Workflows and Components.
_Avoid_: spec, Arazzo file, workflow file

**Source description** (`Arazzo.SourceDescription`):
A named reference to an OpenAPI or AsyncAPI description, or to another Arazzo Document, that Steps target. This library records the reference and never fetches it.
_Avoid_: API, service, source document

**Specification extension** (`VendorExtensions`):
An `x-`prefixed field allowed on every extensible object, kept as `JSONValue` in key order.
_Avoid_: custom field, metadata

## Workflows and steps

**Workflow** (`Arazzo.Workflow`):
A named sequence of Steps with its own inputs, outputs, parameters and actions, identified by `workflowId`.
_Avoid_: flow, scenario, journey

**Step** (`Arazzo.Step`):
One call inside a Workflow, identified by `stepId`, with exactly one Target.
_Avoid_: request, task, call (as the noun)

**Target** (`Arazzo.Step.Target`):
What a Step invokes: an `operationId`, an `operationPath`, an AsyncAPI `channelPath`, or another Workflow's `workflowId`. Exactly one, enforced by the enum.
_Avoid_: endpoint, operation (when the Target is a Workflow)

**Operation**:
An API operation in a Source description, reached by `operationId` or `operationPath`. It belongs to the Source description, not to this library.
_Avoid_: Step

**Async step**:
An Arazzo 1.1 Step targeting an AsyncAPI channel, with an `action` (send/receive), `correlationId` and `timeout`.

**Parameter** (`Arazzo.Parameter`):
A named value with a location (`in`: path, query, header, cookie, or 1.1's `querystring`) passed to an Operation. Parameters set on a Workflow apply to its Steps; a Step's own Parameter overrides one with the same name and location.

**Effective parameters / actions**:
What actually applies to a Step after merging Workflow-level values with Step overrides and resolving Reusables (`Document.effectiveParameters(for:in:)`, `effectiveSuccessActions`, `effectiveFailureActions`).
_Avoid_: merged, final

**Execution order**:
An order of a Workflow's Steps that respects `dependsOn` and `$steps` references (`Workflow.executionOrder(components:)`). A cycle is a `DependencyCycleError`. Computing it is not executing the Workflow, which is out of scope.

## Outcomes

**Criterion** (`Arazzo.Criterion`):
One check on a Step's result: a Simple condition, a `regex`, a `jsonpath` query or an `xpath` query, evaluated against a context expression. A Step succeeds when every success Criterion is satisfied.
_Avoid_: assertion, rule (that is a Validation rule)

**Simple condition** (`Arazzo.Condition`):
The Specification's expression language for Criteria, such as `$statusCode == 200 && $response.body#/id != null`. String comparisons are case-insensitive and numeric strings coerce.
_Avoid_: predicate, filter (that is JSONPath)

**Expression type** (`Arazzo.ExpressionType`):
The `type` and `version` of a Criterion or Selector. For JSONPath, the version picks the Dialect.

**Success action / Failure action** (`Arazzo.SuccessAction`, `Arazzo.FailureAction`):
What happens after a Step: `end`, `goto` a Step or Workflow, or (failure only) `retry` with `retryAfter` and `retryLimit`. Each may carry its own Criteria.
_Avoid_: handler, callback

**Output** (`Arazzo.OutputValue`):
A named value a Step or Workflow exposes: a Runtime expression, or in 1.1 a Selector.

**Selector** (`Arazzo.Selector`):
An Arazzo 1.1 object that extracts a value from a context with a JSONPath, XPath or JSON Pointer query. A Selector matching several Nodes yields an array.

**Payload replacement** (`Arazzo.PayloadReplacement`):
A change to a request body payload at a target location, applied by `RequestBody.resolvedPayload(in:)`.

## Expressions

**Runtime expression** (`Arazzo.RuntimeExpression`):
A `$`-prefixed reference to runtime data (`$statusCode`, `$inputs.x`, `$steps.s.outputs.o#/ptr`), parsed into a typed `Kind` following the Specification's ABNF. Unparseable text is kept as `.invalid` and reported by validation.
_Avoid_: variable, placeholder, JSONPath

**Expression template** (`Arazzo.ExpressionTemplate`):
A string with embedded `{$…}` Runtime expressions, rendered by substituting each one.
_Avoid_: interpolated string, format string

**Evaluation context** (`Arazzo.EvaluationContext`):
The runtime state (status code, request, response, inputs, Step outputs…) against which expressions and Criteria are evaluated. Callers fill it in or conform their own runtime to `RuntimeExpressionResolver`.
_Avoid_: environment, state, session

**Query evaluator** (`Arazzo.QueryEvaluator`):
The plug-in point for query languages this library does not implement, today XPath.

## Reuse

**Components** (`Arazzo.Components`):
The Document's library of reusable inputs, parameters, success actions and failure actions.

**Reusable** (`Arazzo.Reusable`, `Arazzo.ReusableOr<T>`):
A `reference` to a Component (`$components.parameters.x`), optionally with a `value` override, used where an inline object could be.
_Avoid_: `$ref` (that is JSON Schema's, for inputs)

## Validation

**Validation rule** (`Arazzo.ValidationRule`):
A named check over a whole Document. The default set encodes the Specification: MUST becomes an error, SHOULD a warning. Callers add or remove rules by name.
_Avoid_: lint, Criterion

**Validation issue** (`Arazzo.ValidationIssue`):
One finding: a Severity, a JSON Pointer path to the offending location, a message and the name of the rule that raised it.
_Avoid_: error (a warning is also an issue)

**Strict decoding** (`Arazzo.DecodingOptions`):
An opt-in mode rejecting unknown properties, fields irrelevant to an action's type, and invalid expressions. The default is **lenient**: decode what can be decoded and leave the findings to validation.

## JSONPath

**Dialect** (`JSONPath.Dialect`):
Which JSONPath language a query is written in: `rfc9535` (strict, the default) or `jayway` (Goessner-derived, with Jayway operators and path functions). Their filters differ: RFC 9535 filters an object's members, Jayway filters the object itself.
_Avoid_: flavour, mode, version (that is the Expression type's field that selects the Dialect)

**JSONValue** (`JSONValue`):
The library's order-preserving JSON value, used for every `Any`-typed field and for query input and output.
_Avoid_: JSON (alone), Any

**Node**:
A value a query selects, together with its Normalized path.

**Normalized path** (`NormalizedPath`):
RFC 9535's canonical, unique path to one Node, such as `$['store']['book'][0]`.
_Avoid_: JSON Pointer, location

**JSON Pointer** (`JSONPointer`):
RFC 6901's `/`-separated reference to a single location. Runtime expressions use it after `#`; Validation issues report one.
_Avoid_: JSONPath, path (alone)
