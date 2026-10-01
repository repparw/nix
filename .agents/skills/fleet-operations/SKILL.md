---
name: fleet-operations
description: Inspect and operate the running NixOS fleet. Use for runtime health, backup status, host diagnostics, or authorized manual activation after configuration verification.
---

# Fleet operations

Use this skill for the running fleet. The generated CLI is the executable
capability surface; discover the installed commands instead of relying on a
copied command list:

```bash
fleet commands --json
```

For configuration edits and pre-deployment confidence, use
[verify-nixos-config](../verify-nixos-config/SKILL.md). That skill evaluates
and builds without activation. A successful build does not prove runtime
health.

## Inspect first

Use the discovered `fleet` commands for runtime inspection. The current
surface includes health probing, offsite backup status, and bounded host debug
bundles. Prefer `fleet debug <host>` over ad-hoc SSH command collections so the
same diagnostic contract works locally and remotely.

Inspection commands are read-only. Report unreachable hosts and unavailable
state rather than silently treating missing evidence as healthy.

## Activation boundary

`fleet update` delegates to the shared `host-update` manual path and can switch
the local host. Run it only when the user has authorized activation. Do not use
it as part of `verify-nixos-config`.

The controller-side production deployment transaction remains the separate
`fleet-update` command documented in the
[fleet runbook](../../../docs/runbooks/fleet-operations.md). Do not substitute
`fleet update` for `fleet-update deploy`; they intentionally have different
roles.

## Report

For operational work, record the host(s), command(s), observed runtime state,
and any unreachable or permission-limited evidence. For an activation, also
report the pre-activation verification used and the post-activation health
result.
