# Coding standards

Read during review. Each rule is a judgement call; mechanical rules live in `CONSTRAINTS.md`.

## Simplicity

- **Boring code.** The minimum that solves the stated problem: no options, parameters or variants nobody asked for, no protocol or abstraction with a single user. A plain `if`/`switch` over an enum beats a pattern. If it could be a quarter of the length, it should be.
- **Surgical diffs.** Every changed line traces to the request; adjacent code, comments and formatting stay as they were. Orphans the change creates are removed in the same change.
- **Matches its surroundings.** New code follows the naming, comment density and idioms of the file it lands in (e.g. `Hashable, Sendable` on every model, `VendorExtendable` on every extensible object, `OrderedDictionary` for map-typed fields).

## Specification fidelity

- **The spec decides.** Behaviour follows the Arazzo specification (and RFC 9535 for the default JSONPath dialect). MUST becomes a validation error, SHOULD a warning. A deliberate leniency is documented in the README and, where it can mislead, flagged by validation.
- **Lossless round trips.** Decoding then encoding preserves key order (`OrderedDictionary`), unknown-but-allowed content (`JSONValue`) and specification extensions.
- **Lenient by default, strict on request.** Default decoding keeps going and leaves the finding to `validate()`; strict `DecodingOptions` reject. Structural impossibilities always fail decoding with a coding path.
- **Domain language.** Types, docs and messages use the terms in `GLOSSARY.md`, not the words under _Avoid_. A new concept gets a glossary entry in the same change.

## Compile-time safety

- **Make misuse unrepresentable.** Mutually exclusive fields become an enum (`Step.Target`); constrained strings become a typed wrapper (`RawRepresentable` + `ExpressibleByStringLiteral`, like `SpecificationVersion`); parsed text becomes a typed AST rather than a string checked later.
- **Failures are typed values.** Parsers and evaluators `throw` a dedicated error type (`ParseError`, `EvaluationError`, `ResolutionError`, …) that says what failed and where. An optional return is for genuine absence (a lookup by ID), not to hide why something failed. Errors name the offending path or expression, never echo a whole payload.
- **Sendable value types.** Public models are `struct`/`enum`, `Sendable` and `Hashable`, so tests compare whole values. Shared mutable state, if it ever appears, lives in an `actor`; `@unchecked Sendable` needs a comment proving safety.
- **Pure library.** Callers pass data in; the library performs no I/O, reads no clock, generates no UUIDs and touches no singletons. Extension points are protocols the caller conforms to (`QueryEvaluator`, `RuntimeExpressionResolver`).
- **Platforms structurally.** Platform differences go behind `#if canImport(…)` / `#if os(…)`, matching the existing `FoundationEssentials` fallback.

## Docs

- **Docs in the same change.** Public API or behaviour changes update the DocC comment, every affected README section or table, and `ReadmeTests` (see `AGENTS.md`). A stale doc is a defect: wrong documentation is worse than none.
- **Doc comments explain why.** Document constraints, spec references and non-obvious semantics; skip restating names and signatures.

## Tests

- **Swift Testing only.** `@Suite`, `@Test`, `#expect`, `#require`; no XCTest.
- **Given / When / Then.** Each test has those three phases (comments when the test is longer than a few lines) and asserts one behaviour; related `#expect`s sit together under _Then_.
- **Isolated.** Each test builds its own values and fixtures; no shared mutable state, so the default random order always passes.
- **Spec examples as fixtures.** Behaviour from the specification is tested against the published examples or conformance suites, copied unmodified with their licence noted in `Fixtures/README.md`; an adaptation of an upstream test is commented where it happens.
