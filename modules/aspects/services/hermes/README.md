# Hermes state and recovery

Hermes owns its runtime settings and OAuth credentials. Preserve the writable
profile when rebuilding or restoring the service. Rebuilding Nix configuration
does not recreate an OAuth grant.

Keep `.env` writable by Hermes. Passing deployment credentials through the
service environment avoids replacing settings saved by Hermes during activation.
The service wiring belongs in [hermes.nix](../hermes.nix).

OAuth deliberately limits T3 access to `orchestration:read` and
`orchestration:operate`. A linked environment's full-access grant does not
raise that client permission ceiling.

If OAuth authorization expires or is revoked, run `hermes mcp login t3code`
as the Hermes user in its existing profile. Complete the human approval step;
for a headless container, forward the loopback callback to the browser's machine
or paste the redirect URL into the login prompt.
Check `hermes mcp test t3code`, then verify a Hermes-initiated read on the relay
and its linked environments. A successful login alone does not prove remote access.
