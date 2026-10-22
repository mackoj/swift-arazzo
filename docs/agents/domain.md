# Domain Docs

## Layout

Single-context: `GLOSSARY.md` at the repository root and `docs/adr/` for architectural decisions.

## Before exploring

- Read `GLOSSARY.md`.
- Read ADRs relevant to the area being changed.
- During review, also read `CODING_STANDARDS.md`.
- For specification behaviour, read the Arazzo specification section or RFC 9535 rule in question; the README lists where this library deliberately departs from them.

If domain documentation is missing, proceed silently.
Create it lazily when domain terms or decisions are resolved.

## Vocabulary and decisions

Use the glossary's terms in code, issues, proposals and tests.
Avoid its explicitly discouraged synonyms.
Add newly introduced domain concepts to the glossary in the same change.

Surface conflicts with existing ADRs explicitly.
A departure from an ADR requires a new or superseding ADR explaining why.
