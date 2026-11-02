# Verification routes

Select the route from the **observable effect**, not from the filename that
changed. Combine routes when the claim spans multiple generated artifacts.

- [Effective values](effective-values.md): resolve NixOS or Home Manager
  options on all affected hosts, including composition/defaults.
- [Systemd units](systemd-units.md): inspect the generated service or timer
  text, including ordering and command-line behavior.
- [Home Manager files](home-manager-files.md): inspect a generated user file
  when evaluating the underlying option does not prove its serialized content.
- [Focused executable checks](focused-checks.md): exercise an existing test
  or package build when behavior cannot be established from static output.

These are checks of the **proposed** configuration. A unit's presence does not
prove it starts; a test VM is not the production fleet; and a native build does
not prove deployment. Use [fleet-operations](../../fleet-operations/SKILL.md)
for authorized live checks.
