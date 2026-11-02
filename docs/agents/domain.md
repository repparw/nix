---
type: Agent Guide
title: Domain Docs
description: How agents should find and use repository domain context.
when: Read when modeling domain concepts, naming changes, or evaluating decisions.
tags: [agents, domain, context]
---

# Domain Docs

Use `docs/` as the repository's single-context domain knowledge. Architecture
and service docs describe behavior and boundaries; a root `GLOSSARY.md`, when
present, defines the agreed domain vocabulary.

## Before exploring

Read the relevant context first:

- `GLOSSARY.md` at the repository root, if present.
- Relevant architecture docs and ADRs under `docs/`, if present.
- The [documentation index](../index.md) to find related pages.

If a page or directory is absent, continue with the available documentation.

## Domain vocabulary

Use terms defined in `GLOSSARY.md` when naming concepts in issues, proposals,
hypotheses, and tests. Avoid introducing synonyms for established terms.

When changing the domain model or resolving ambiguous terminology, use the
installed `domain-modeling` skill: compare the proposed meaning with the code,
test it against concrete edge cases, and record terms only once their meaning
is settled. Create `GLOSSARY.md` lazily; keep implementation details in the
architecture docs, not the glossary.

## Decisions

If proposed work contradicts an existing ADR, identify the conflict explicitly
instead of silently overriding the decision.

Record a new decision in `docs/adr/` only when it is hard to reverse, surprising
without context, and represents a genuine choice between alternatives. Do not
turn routine configuration changes or the existing decision log into ADRs.
