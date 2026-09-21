# Inspect generated Home Manager files

Use the setup in [SKILL.md](../SKILL.md), then build the selected user's
activation package and read the file the change targets:

```bash
HOME_OUTPUT=$(bash "$VERIFY_BUILD" \
  ".#nixosConfigurations.$VERIFY_HOST.config.home-manager.users.repparw.home.activationPackage" \
  "$VERIFY_EVIDENCE")
jq -r '.agent | to_entries[] | "\(.key): \(.value.model)"' \
  "$HOME_OUTPUT/home-files/.config/opencode/opencode.json" \
  | tee "$VERIFY_EVIDENCE/agent-models-$VERIFY_HOST.txt"
```

Compare the observed values with the task's expected values. Replace the
example file and query for other dotfiles. Files are under
`home-files/<path-in-home>` inside the returned output.

This checks generated home configuration. System configuration requires the
relevant [evaluation](flake-eval.md) or [system build](system-build.md).
