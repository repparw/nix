# Verification routes

Choose a route by the effect you want to observe, not by which file changed.
Combine routes when the claim covers more than one generated artifact.

- [Effective values](effective-values.md). Resolve NixOS or Home Manager options
  on every affected host, including defaults and composition.
- [Systemd units](systemd-units.md). Read the generated service or timer text,
  including ordering and command-line behavior.
- [Home Manager files](home-manager-files.md). Read a generated user file when
  evaluating the option does not prove the file's serialized content.
- [Focused executable checks](focused-checks.md). Run an existing test or
  package build when static output cannot establish the behavior.

These routes check the proposed configuration only. A unit that exists may still
fail to start. A test VM is not the production fleet. A native build does not
prove a deployment. For authorized live checks, use
[fleet-operations](../../fleet-operations/SKILL.md).
