# Grafana Cloud incident triage

Grafana Cloud remains the source of truth for alert rules, contact points and
notification policies. This opt-in receiver does not replace normal Discord
alerts or change deployment/rollback behavior.

## Delivery path

1. The existing Cloudflare Tunnel for `repparw.com` routes the exact HTTPS
   path `/hooks/grafana` through Epsilon Traefik to a loopback HTTP receiver.
   No new public port or DNS name is required.
2. In Grafana Cloud, add a **Webhook** integration to the existing contact
   point that already delivers to Discord. This preserves the current
   notification-policy routing and Discord delivery; all notifications reach
   the receiver but it ignores alerts without the selected labels. Use
   `https://repparw.com/hooks/grafana`, method POST, authorization header
   scheme `Bearer`, and a separate 32+-character random token in
   **Authentication Header Credentials** (not the URL). This must match the
   Epsilon `modules.grafana-alert-triage.tokenFile` secret. Alternatively,
   use a separate contact point only after proving that a matching child
   notification policy will not bypass the existing Discord route.
3. The receiver accepts only firing/resolved alert instances with known fleet
   `host` labels. It queues only explicitly opted-in
   `agent_triage="true"` (or `"1"`) alerts, or
   `severity="critical"` alerts with a `service` label.
4. Events are validated, length-limited, deduplicated by alert fingerprint
   and start time, and stored under
   `/var/lib/grafana-alert-triage/events`. Resolved alerts cancel pending
   investigations. Grafana receives HTTP 202 on successful intake.
5. The state directory is mounted into the existing Hermes container.
   An explicitly enrolled `Fleet alert triage` cron job runs every 5 minutes,
   researches actionable incidents, and reports to Hermes's existing WhatsApp
   destination. Failed jobs retain pending events for a bounded retry.

## Activation is intentionally separate

This PR does not add a token to the repository or enable the listener. After
review, create a dedicated encrypted SOPS token and provision it on Epsilon.
Then configure:

```nix
modules.grafana-alert-triage = {
  enable = true;
  tokenFile = config.sops.secrets.grafana-alert-triage-token.path;
};
```

Declare the SOPS secret separately with runtime-only delivery and
`restartUnits = [ "grafana-alert-triage.service" ];`, so a token rotation
restarts the receiver and refreshes its systemd credential. A missing or
unreadable credential must leave the receiver unavailable, not unauthenticated.
The listener uses systemd LoadCredential and runs as Epsilon's
user-namespace-mapped Hermes UID (328025), not root.

After deploying Epsilon, configure the Grafana Cloud contact point, enroll
`alert_triage_enroll.py` from within Hermes's installed Python environment,
and use the Grafana contact point's **Custom test** to supply
`host=epsilon`, `service=test`, and `agent_triage=true` labels. A
predefined test may return HTTP 202 but queue zero incidents, since the
receiver deliberately ignores alerts without a known `host` label and
triage opt-in. Check receiver journals, persisted events, cron status and
WhatsApp. Disable or resolve the disposable test alert before leaving. Do not manufacture a
real production outage. Never commit unredacted Grafana Cloud exports.

## Security and boundaries

- Requests require a constant-time-checked bearer credential and are capped
  at 64 KiB. Invalid requests do not launch an agent.
- Only selected fields from the Grafana alert are stored; message bodies,
  labels and annotations are treated as untrusted. No shell commands or URLs
  supplied by an alert are executed.
- The receiver listens on 127.0.0.1, behind the existing tunnel and Traefik.
  No Grafana credentials, host SSH keys or repair privileges are given to the
  Hermes alert cron job.
- The triage agent currently uses web research and the supplied alert facts.
  It **does not have live host logs or Grafana query access** and must not
  claim otherwise. If a diagnosis needs host evidence, it describes exact
  read-only checks for an operator. Adding restricted live diagnostics would
  be a separate, reviewed change.
- This is a diagnostic notification path. It never rolls back, restarts
  services, applies fixes, deploys or silences alerts.
- Cloud contact point and notification configuration are not Git-synced.
  Merging this PR alone does not enable the pipeline. Keep existing Discord
  routing independent until a live firing and resolved test has passed.

## Offline check

```sh
nix build .#checks.x86_64-linux.grafana-alert-triage --no-link
```
