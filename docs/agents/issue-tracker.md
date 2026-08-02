---
type: Agent Guide
title: Issue Tracker: GitHub
description: Conventions for GitHub Issues, PRDs, and work tickets.
when: Read when creating, fetching, claiming, or resolving repository work tickets.
tags: [agents, github, issues]
---

# Issue tracker: GitHub

Issues, PRDs, and work tickets live in GitHub Issues for `repparw/nix`. Use the `gh` CLI and infer the repository from the GitHub `origin` remote.

## Conventions

- Publishing to the issue tracker means creating a GitHub issue.
- Fetching a ticket means reading the issue, its labels, and its comments.
- Pull requests are not a triage request surface.
- A bare issue or PR number may be ambiguous because GitHub shares their number space.

## Wayfinding

- A map is an issue labelled `wayfinder:map`.
- Child tickets use GitHub sub-issues and `wayfinder:<type>` labels.
- Use native issue dependencies for blocking relationships.
- Claim work by assigning the issue to yourself before making changes.
- Resolve work by recording the answer, closing the issue, and adding its context pointer to the map.
