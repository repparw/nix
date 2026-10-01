# Verification checks

Choose the checks that observe the changed behavior. Run more than one when
needed, and report relevant checks that were skipped.

| Check                                       | What it proves                                                                      | Cost           |
| ------------------------------------------- | ----------------------------------------------------------------------------------- | -------------- |
| [flake-eval](flake-eval.md)                 | Affected host configurations evaluate and changed options have the expected values. | Seconds        |
| [home-manager-files](home-manager-files.md) | Generated dotfiles contain the intended configuration.                              | About a minute |
| [system-build](system-build.md)             | The selected system closure builds.                                                 | Minutes        |
| [closure-diff](closure-diff.md)             | Package differences from the running target system.                                 | Minutes        |

Builds do not run commit hooks or prove activation and service health.
Deployment and runtime checks follow the
[fleet-operations skill](../../fleet-operations/SKILL.md) and
[fleet runbook](../../../../docs/runbooks/fleet-operations.md).
