# Issue tracker: GitHub

Issues and specifications live in GitHub Issues for mackoj/swift-arazzo. Use the gh CLI.

## Conventions

- Infer the repository from origin; outside the clone, pass --repo mackoj/swift-arazzo.
- Read: gh issue view <number> --json number,title,body,labels,comments.
- List: gh issue list --state open --json number,title,labels.
- Create: gh issue create --title "..." --body-file <file>.
- Comment: gh issue comment <number> --body-file <file>.
- Label: gh issue edit <number> --add-label "..." or --remove-label "...".
- Close: gh issue close <number>.
- Use actual newlines in body files.
- Apply ready-for-agent to fully specified issues ready for agent work.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill instructions

"Publish to the issue tracker" means create a GitHub issue.
"Fetch the relevant ticket" means read the GitHub issue and its comments.

## Wayfinding

A map is an issue labelled wayfinder:map. Link its tickets as GitHub sub-issues,
or use a task list and "Part of #<parent>".
Use wayfinder:research, wayfinder:prototype, wayfinder:grilling
or wayfinder:task for child tickets.

Record blockers with native GitHub issue dependencies where available;
otherwise use "Blocked by: #<number>" in the issue body.
Only claim an unassigned ticket whose blockers are all closed.
