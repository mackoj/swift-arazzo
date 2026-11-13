# Measuring and profiling

The benchmarks live in `Benchmarks/`, a separate package on [package-benchmark](https://github.com/ordo-one/package-benchmark),
so ArazzoKit never depends on it. Run everything from the repository root.

## Measure a change

Save `main`'s numbers before you change code, then compare the same harness after:

```sh
swift package --package-path Benchmarks benchmark --format markdown --no-progress > .build/before.md
# … change the code …
swift package --package-path Benchmarks benchmark --format markdown --no-progress > .build/after.md
swift run --package-path Benchmarks -c release p50 .build/before.md .build/after.md
```

`p50` prints a Markdown table of each benchmark's median wall clock and mallocs, before → after, ready for the pull
request. Malloc and retain counts are deterministic; wall clock moves a few percent between runs, so rerun a benchmark
before trusting a small change.

- `--filter` takes one regular expression per flag and runs the benchmarks that match any of them: repeat the flag
  (`--filter 'Parse conditions' --filter 'Validate.*'`) rather than writing `A|B`.
- The large benchmarks report microseconds; the per-operation ones (`scalingFactor: .kilo`) report nanoseconds per
  operation, marked `*` in package-benchmark's tables.
- `benchmark baseline update` / `baseline compare` are package-benchmark's own thresholds and stay available; `p50` is
  for reading the difference at a glance.

## Profile a benchmark

```sh
Benchmarks/scripts/profile.sh 'Validate, large' 25
```

It runs that one benchmark under Instruments' Time Profiler and prints:

- **Self**: the functions the samples were in. Standard library entries here say what kind of work dominates
  (`_swift_stdlib_getBinaryProperties` is Unicode property lookups, `_xzm_malloc` allocation, `swift_retain` reference
  counting).
- **Inclusive**: the ArazzoKit, JSONPath and Yams functions with the most samples under them, which says whose work it
  is.

The trace stays in `Benchmarks/.build/profiles/` to open in Instruments. package-benchmark's ARC and malloc counting
hooks run only while measuring, so the report leaves out samples inside them.

## What has paid off

- **Read ASCII grammars as bytes or scalars, not `Character`s.** Grapheme breaking and Unicode property lookups were
  the top cost of every parser here. The ABNF is ASCII: scan `utf8` for runtime expressions and templates, and
  `unicodeScalars` where Unicode letters are allowed (condition identifiers). Slice token text from the source rather
  than rebuilding it. See 0.1.1's release notes for the numbers.
- **Avoid recomputing a derived value inside a loop**: a computed property such as `JSONSchema.properties` builds a
  new value on every read.
- Decoding and encoding time is spent in Yams and swift-jsonpath, not here.
