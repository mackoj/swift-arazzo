# ``ArazzoKitBuilder``

Write Arazzo documents in Swift with result builders.

## Overview

`ArazzoKitBuilder` is a thin layer over `ArazzoKit`: its builders produce a plain `Arazzo.Document`, so
`jsonData()`, `yamlString()` and `validate()` work on the result unchanged. It depends only on `ArazzoKit`, which it
re-exports.

```swift
import ArazzoKitBuilder

let document = Arazzo.Document {
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
```

The memberwise initialisers of `ArazzoKit` already read declaratively. The builder adds:

- **Control flow while building**: `if`, `else`, `switch`, `for` and `if #available` in every body, so a document
  can be generated from data.
- **Composition**: a helper that returns a ``Step``, or an `[any StepComponent]` group of parameters, drops into any
  body.
- **No wrapping**: `.inline(...)`, `ReusableOr`, `OrderedDictionary` keys and optional arrays stay out of call
  sites.

### Shape rules

- Collections go in the body: parameters, criteria, actions, outputs, steps, workflows, source descriptions and
  components.
- Scalars go in the initialiser or a modifier, such as ``Step/description(_:)`` or ``Workflow/inputs(_:)``, so a
  body never holds two competing values for one field.
- One specification concept is one type: ``Parameter`` works in a workflow, a step and ``Components``.
- References reuse the model: `Parameter.reference("page", value: 2)` and `OnFailure.reference("backoff")` become
  Reusable Objects.

### What the builder does not do

It builds what you wrote. It does not validate, throw or trap: call `validate()` on the result. Keyed fields keep
the last value written, so two `Output("name", ...)` in one step, or two components with one name, leave one entry.
Validation cannot see the earlier one.

The type names are top-level and can collide with your own `Workflow` or `Step`. Qualify them as
`ArazzoKitBuilder.Step` when they do.

## Topics

### Documents

- ``Info``
- ``Source``
- ``Workflow``
- ``Components``

### Workflows and steps

- ``Step``
- ``Input``
- ``Parameter``
- ``RequestBody``
- ``SuccessCriterion``
- ``Output``

### Actions

- ``SuccessAction``
- ``FailureAction``
- ``OnSuccess``
- ``OnFailure``

### Builders

- ``DocumentBuilder``
- ``WorkflowBuilder``
- ``StepBuilder``
- ``ComponentsBuilder``
- ``DocumentComponent``
- ``WorkflowComponent``
- ``StepComponent``
- ``ReusableComponent``
