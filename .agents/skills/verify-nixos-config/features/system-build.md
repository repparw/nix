# Build the system closure

Use the setup in [SKILL.md](../SKILL.md):

```bash
SYSTEM_OUTPUT=$(bash "$VERIFY_BUILD" \
  ".#nixosConfigurations.$VERIFY_HOST.config.system.build.toplevel" \
  "$VERIFY_EVIDENCE")
printf '%s\n' "$SYSTEM_OUTPUT" > "$VERIFY_EVIDENCE/system-$VERIFY_HOST.txt"
```

A zero exit status and returned store path prove that this closure built.
The helper saves the build log and preserves a failing Nix exit status.
An evaluation error can be investigated with [flake-eval](flake-eval.md).

The build does not activate the system, run commit hooks, or prove service
health. Cross-architecture targets may need a suitable builder. Prefer the
lighter checks for changes they can observe directly.
