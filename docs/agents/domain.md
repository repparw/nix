# Domain Docs

This repository uses a single-context domain-doc layout.

## Before exploring

Read these when they exist:

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If either is absent, proceed silently. Domain-modeling workflows create them lazily when terminology or decisions crystallize.

The broader architecture and operational documentation lives under `docs/`.
Read the relevant sections there as additional project context.

## Expected structure

```text
/
├── CONTEXT.md
└── docs/
    ├── adr/
    ├── agents/
    ├── architecture/
    ├── decisions/
    ├── hosts/
    ├── runbooks/
    └── services/
```

## Domain vocabulary

Use terminology defined in `CONTEXT.md` when naming concepts in issues, proposals, hypotheses, and tests. Avoid drifting to synonyms that the glossary rejects.

A missing term may indicate either unsuitable invented language or a genuine gap to address through domain modeling.

## ADR conflicts

If proposed work contradicts an existing ADR, identify the conflict explicitly rather than silently overriding the decision.
