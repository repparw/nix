---
type: Agent Guide
title: Domain Docs
description: How agents should find and use repository domain context.
when: Read when modeling domain concepts, naming changes, or evaluating decisions.
tags: [agents, domain, context]
---

# Domain Docs

Use `docs/` as the repository's single-context domain knowledge.

## Before exploring

Read the relevant context first:

- `CONTEXT.md` at the repository root, if present.
- Relevant architecture docs and ADRs under `docs/`, if present.
- The [documentation index](../index.md) to find related pages.

If a page or directory is absent, continue with the available documentation.

## Domain vocabulary

Use terminology defined in `CONTEXT.md` when naming concepts in issues,
proposals, hypotheses, and tests. Avoid introducing synonyms for established
terms.

A missing term may indicate either unsuitable invented language or a genuine gap to address through domain modeling.

## Decisions

If proposed work contradicts an existing ADR, identify the conflict explicitly
instead of silently overriding the decision.
