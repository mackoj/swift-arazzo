# Constraints

Last reviewed: 2026-10-22

## Floor

- No new checker suppressions (`swiftlint:disable`, `@available(*, deprecated)` to silence warnings), disabled or skipped tests (`.disabled`, `withKnownIssue` without a linked issue), `fatalError("TODO")`-style stubs, or secrets in source.
- No deleted tests or removed assertions without a reason in the commit message.
- Fixtures under `Tests/*/Fixtures/` stay byte-identical to upstream; an upstream bug is asserted by a test, not fixed in the fixture.
- Do not weaken this file to make a change pass.

## Enforced checks

Run these before handing back a code change; each must pass.

| Dimension | Rule | Checked by |
|-----------|------|------------|
| Diff integrity | 0 whitespace errors | `git diff --check main` |
| Compilation | 0 errors, debug and release | `swift build --build-tests`, `swift build -c release` and `swift build --disable-default-traits` |
| Behaviour | 0 failing tests, including the official Arazzo examples and README examples | `swift test` |
| Formatting | 0 changes from formatting, 0 lint findings, with swift-format 6.3 | `swift-format lint --strict --parallel --recursive Sources Tests Package.swift Package@swift-6.0.swift Architecture Benchmarks` |
| Architecture rules | 0 findings from the rules in `docs/architecture-rules.md`, no baseline, and the rules document up to date | `swift test --package-path Architecture` (macOS) |
| Public API | 0 breaking changes against the base branch, unless intended and called out in the pull request | `swift package diagnose-api-breaking-changes main` |
| Documentation | 0 DocC warnings for the `.spi.yml` targets | Soundness workflow's documentation check (CI) |
| Workflows and YAML | 0 findings | `actionlint`, `zizmor .github/workflows` and `yamllint --strict .` |
| ArazzoKit dependency budget | `ArazzoKit` depends only on swift-jsonpath's `JSONPath`, `ArazzoKitBuilder` only on `ArazzoKit`, and Yams stays behind the `YAML` trait; `import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)` | `Package.swift` review and `grep -rn -B3 '^import Foundation$' Sources/ArazzoKit` |

Linux and Swift 6.0 are where a change most often breaks (no Objective-C Foundation, an older compiler and Swift Testing): CI runs Swift 6.0, 6.1 and 6.2 in Linux containers. Check the oldest one locally with Apple's `container` CLI (`container system start` once), which builds in its own scratch path:

```sh
container run --rm -v "$PWD":/src -w /src swift:6.0 swift test --scratch-path .build/linux-6.0
```

Older swiftly toolchains do not build against the current macOS SDK, so the container is the local check. When a change touches Foundation APIs, regexes, platform guards or test macros, run it or say you left it to CI.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|----|------|------|--------|-------|---------|
