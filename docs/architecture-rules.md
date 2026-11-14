# Architecture rules

The mechanical part of `CODING_STANDARDS.md` and `CONSTRAINTS.md`, enforced by the `Architecture/` package with [swift-llm-check](https://github.com/mackoj/swift-llm-check): `swift test --package-path Architecture` (macOS). Generated from its rules; do not edit by hand.

## purity

The library is pure. Read before you reach for the file system, the network, a clock or a UUID.

### The library performs no I/O, reads no clock, makes no UUID and touches no singleton.

`library-performs-no-io`: swift-arazzo is a pure library (CODING_STANDARDS.md, "Pure library"): callers pass data in and get values back, so the same input gives the same output on every platform and in every test. A file read, a network call, `Date()`, `UUID()`, a `.shared` or `.default` singleton or `print` makes results depend on the machine, and `print` writes to a host's standard output.

**How to fix:** Take the value as a parameter, or add an extension point the caller conforms to, like `QueryEvaluator` or `RuntimeExpressionResolver`. Report a problem as a thrown error or a `ValidationIssue`, never by printing.

Bad:

```swift
let document = try Arazzo.Document(json: Data(contentsOf: url))  // Data(contentsOf:) reads via FileManager
let runID = UUID()
```

Good:

```swift
public init(json data: Data, options: Arazzo.DecodingOptions = .init()) throws  // the caller reads the file
public func evaluate(in context: some RuntimeExpressionResolver) throws -> Bool  // the caller supplies state
```

## platforms

Imports and the dependency budget. Read before you add an `import` to `Sources`.

### `import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)`.

`foundation-falls-back-from-essentials`: On Linux, FoundationEssentials is the small, Codable-only part of swift-foundation; full Foundation pulls in ICU and everything else. The library needs only the essentials, so it imports them where they exist and falls back to Foundation elsewhere (CONSTRAINTS.md, "ArazzoKit dependency budget").

**How to fix:** Wrap the import in the same guard as `Sources/ArazzoKit/Model/Document.swift`.

Bad:

```swift
import Foundation
```

Good:

```swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
```

### ArazzoKit imports only JSONPath and Foundation; Yams is imported only under `#if YAML`.

`imports-stay-within-budget`: ArazzoKit's dependency budget is swift-jsonpath alone, and YAML support stays behind the `YAML` package trait so a client that turns the trait off never builds Yams (CONSTRAINTS.md, "ArazzoKit dependency budget"). An extra import in ArazzoKit is an extra dependency for every client.

**How to fix:** Implement the feature with the standard library, FoundationEssentials or JSONPath. Code that needs Yams belongs in ArazzoKitYAML, inside its `#if YAML` block. A new dependency is a decision for the maintainer, recorded in `Package.swift`, `Package@swift-6.0.swift` and CONSTRAINTS.md first.

Bad:

```swift
// Sources/ArazzoKit/Model/Document.swift
import Yams
```

Good:

```swift
// Sources/ArazzoKitYAML/ArazzoYAML.swift
#if YAML
import ArazzoKit
import Yams
```

## models

Public types and concurrency. Read before you add or change a public type.

### A public struct or enum in `Sources/ArazzoKit/Model` is declared `Hashable` and `Sendable`.

`public-models-are-hashable-and-sendable`: Models are values (CODING_STANDARDS.md, "Sendable value types"): `Sendable` lets clients share a decoded document across tasks under Swift 6, and `Hashable` lets tests compare whole documents rather than fields one by one. A missing conformance is a source break to add later, since a client cannot add it.

**How to fix:** Declare both on the type itself, like its neighbours: `public struct Step: Hashable, Sendable, …`.

Bad:

```swift
public struct Criterion: VendorExtendable {
```

Good:

```swift
public struct Criterion: Hashable, Sendable, VendorExtendable {
```

### An `@unchecked Sendable` conformance has a comment that proves it safe.

`unchecked-sendable-explains-itself`: `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types"); shared mutable state belongs in an `actor` instead.

**How to fix:** Prefer a value type or an `actor`. If neither fits, put a `//` comment (not a `///` doc comment) just above the declaration, or at the start of its body, that says what guards the mutable state.

Bad:

```swift
final class Cache: @unchecked Sendable {
```

Good:

```swift
// Every access to `storage` holds `lock`.
final class Cache: @unchecked Sendable {
```

## testing

Swift Testing, and no silenced tests. Read before you add, skip or mark a test.

### Tests use Swift Testing, never XCTest.

`tests-use-swift-testing`: The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and `#require` give one failure message style, parameterised tests and parallel, randomly ordered runs.

**How to fix:** Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.

Bad:

```swift
import XCTest
final class ConditionTests: XCTestCase { func testEquality() { XCTAssertTrue(…) } }
```

Good:

```swift
import Testing
@Suite struct ConditionTests { @Test func equality() { #expect(…) } }
```

### `withKnownIssue` names the issue that tracks it.

`known-issues-explain-themselves`: A known issue hides a failing expectation. Without a reason and a link, the next reader cannot tell a bug waiting for a fix from a test nobody understood, and nobody removes it once the bug is fixed (CONSTRAINTS.md, "Floor").

**How to fix:** Pass the reason as the first argument, with the GitHub issue that tracks it.

Bad:

```swift
withKnownIssue { try validate(document) }
```

Good:

```swift
withKnownIssue("Upstream example uses a 1.1 field in a 1.0 document (mackoj/swift-arazzo#12)") {
    try validate(document)
}
```

### No test or suite is `.disabled`.

`tests-are-not-disabled`: A disabled test still reads as coverage while checking nothing (CONSTRAINTS.md, "Floor"). A failing behaviour is either fixed, or asserted as a known issue that names its tracking issue.

**How to fix:** Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue("…#N")`.

Bad:

```swift
@Test(.disabled("flaky")) func decodesExample() throws {
```

Good:

```swift
@Test func decodesExample() throws {
```

### In `#expect` and `#require`, `try` comes first or not at all.

`try-leads-expectations`: CI builds the tests on Swift 6.0 (CONSTRAINTS.md), whose `#expect` and `#require` expand the expression into a non-throwing autoclosure unless it starts with `try`. A `try` nested inside it, such as `#expect(x == .y(try z()))`, compiles on Swift 6.1 and later and fails on 6.0 with "call can throw, but it is executed in a non-throwing autoclosure".

**How to fix:** Compute the throwing value in a `let` before the expectation, or start the expression with `try`.

Bad:

```swift
#expect(condition == .expression(try .init("$statusCode"), accessors: []))
```

Good:

```swift
let statusCode = try Arazzo.RuntimeExpression("$statusCode")
#expect(condition == .expression(statusCode, accessors: []))
```
