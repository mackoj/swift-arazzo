# Merging and releasing

## Merge a pull request

Merge only when every check is green, and only the commit you checked:

```sh
gh pr checks <number> --watch
gh pr merge <number> --merge --match-head-commit "$(git rev-parse HEAD)"
```

`--match-head-commit` refuses the merge if the branch moved since, so a commit pushed after review is never merged
unchecked, nor left out of a merge someone else made.

## Release

Release after a merge that changes what clients build: `Sources/`, `Package.swift` or `Package@swift-6.0.swift`.
Benchmarks, rules, docs and the site alone need no release.

1. Pick the version. Before 1.0, a breaking change (an API break or a raised Swift or platform floor) bumps the minor
   version; anything else bumps the patch version.
2. Check what the README and `site/index.html` claim. Their install snippets say `from:` the oldest version that has
   the API they document: SwiftPM's `from:` already accepts every later version below the next major, so raise it only
   when they use something new. If the release changes performance, update the benchmark table and figures on the site
   from `docs/performance.md`'s `p50` output. Land these edits through a pull request before tagging.
3. Tag and publish:

   ```sh
   gh release create <version> --target main --title <version> --notes-file notes.md
   ```

   The notes open with what changed for a client in a sentence or two, then a table when performance changed, then
   `## What's Changed` (one line per pull request since the last tag, `* <title> by @<author> in <url>`) and
   `**Full Changelog**: https://github.com/mackoj/swift-arazzo/compare/<previous>...<version>`.
