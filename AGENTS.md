Repo follows upstream `vic/den` default-template structure.

## Core Rules
- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.

- Keep related logic together, usually wrapped in the same aspect
- Put reusable features in dedicated aspect files.

- Do not put plaintext secrets in repo; use `sops-nix`.

Useful after structural changes:
```shell
nix fmt
nix flake check
```

When adding new files or directories, stage them before evaluating. Nix flakes only see tracked files
