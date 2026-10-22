# Agent notes

`swift-arazzo` is a Swift library, not an app: Codable models, runtime expressions, condition evaluation and validation for the Arazzo 1.0/1.1 specification, plus a standalone JSONPath engine. Products and their dependency budget are in `Package.swift`; usage is in `README.md`.

Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.

## Project conventions
- Consult `GLOSSARY.md` for domain terms, `docs/adr/` for decisions and their rationale, and `CODING_STANDARDS.md` for review rules.
- Before the first edit of any task, create a sibling worktree on its own branch: `git worktree add -b <topic> ../swift-arazzo-<topic> main`, and make every change there. The main checkout stays clean on `main`.
- The specification is the source of truth for behaviour. Cite the Arazzo section or RFC 9535 rule a change implements, and record a deliberate deviation (like the dotted-path convenience) in the README and the validation rules.

## How to work
- **Plan first.** For a change spanning several files or with more than one reasonable reading, state your assumptions and a short plan (`step → verify: check`), then wait for approval. Name what is unclear instead of guessing.
- **Test first.** Turn the task into a check before coding: a bug gets a failing test that reproduces it; a feature gets a test that exercises it; a refactor keeps every existing test green before and after.
- **Smallest diff.** Every changed line traces to the request. Match the surrounding file's idioms even where you would write it differently. Remove what your change orphans; mention, rather than delete, pre-existing dead code.

## Docs travel with code
`README.md` is the user documentation and DocC comments are the API reference (Swift Package Index builds docs for `ArazzoKit` and `ArazzoKitYAML`, see `.spi.yml`). In the same change as any API or behaviour change:
- Update the doc comment on every public declaration you touch.
- Update every README section, example and table the change affects (`grep -n "<Symbol>" README.md`), including the specification-coverage table and the built-in rules list.
- Keep README snippets compiling: `Tests/ArazzoKitTests/ReadmeTests.swift` mirrors them, so a changed snippet changes its test.

## Build and test
- `swift build` and `swift test`; one test with `swift test --filter <Suite>/<test>`. Pipe through `xcsift` (configured in `.xcsift.toml`) for compact errors.
- CI (`.github/workflows/ci.yml`) runs macOS and Linux on Swift 6.0, 6.1 and 6.2: code must compile on 6.0 and without Apple-only Foundation.

## Agent skills

### Issue tracker
Issues and specifications live in GitHub Issues for mackoj/swift-arazzo. See `docs/agents/issue-tracker.md`.

### Triage labels
Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs
Single-context layout: root `GLOSSARY.md` and `docs/adr/`. See `docs/agents/domain.md`.
