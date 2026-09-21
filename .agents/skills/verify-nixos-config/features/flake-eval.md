# Evaluate the configuration

Use the setup in [SKILL.md](../SKILL.md). For a shared composition change,
evaluate every affected host's toplevel, not just a release string:

```bash
nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file \
  > "$VERIFY_EVIDENCE/hosts.json"
mapfile -t VERIFY_HOSTS < <(jq -r '.[]' "$VERIFY_EVIDENCE/hosts.json")
for VERIFY_HOST in "${VERIFY_HOSTS[@]}"; do
  nix eval ".#nixosConfigurations.$VERIFY_HOST.config.system.build.toplevel.drvPath" \
    --raw --no-update-lock-file > "$VERIFY_EVIDENCE/toplevel-$VERIFY_HOST.txt"
done
```

For a host-specific change, evaluate that host. Also query the option changed
by the task and check its value. For example:

```bash
nix eval ".#nixosConfigurations.$VERIFY_HOST.config.home-manager.users.repparw.programs.opencode.settings.agent" \
  --json --no-update-lock-file > "$VERIFY_EVIDENCE/agents-$VERIFY_HOST.json"
jq 'map_values(.model)' "$VERIFY_EVIDENCE/agents-$VERIFY_HOST.json"
```

If an option retains its default, inspect aspect composition and
`modules/defaults.nix`. For generated-file changes, continue with
[file inspection](home-manager-files.md).
