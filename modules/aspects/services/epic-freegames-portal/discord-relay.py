#!/usr/bin/env python3
"""Relay epicgames-freegames-node webhook notifications to Discord.

claabs' generic webhook notifier POSTs {account, reason, url} to a URL we
control. The fleet's Discord bot cannot manage channel webhooks (the shape
claabs' own Discord notifier needs), so this local relay reshapes the
payload into the same {content, embeds} message its Discord notifier would
produce and posts it with the bot token from the hermes-env sops secret.
Binds to loopback only: nothing outside pi can trigger Discord messages.
"""

import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

LISTEN_PORT = 3999
CHANNEL_ID = os.environ["DISCORD_CHANNEL_ID"]
TOKEN = os.environ["DISCORD_BOT_TOKEN"]


def post_to_discord(message):
    request = urllib.request.Request(
        f"https://discord.com/api/v10/channels/{CHANNEL_ID}/messages",
        data=json.dumps(message).encode(),
        headers={
            "Authorization": f"Bot {TOKEN}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        print(f"discord-relay: posted message, http {response.status}", flush=True)


class Relay(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            payload = {}
        account = str(payload.get("account", "")) or "unknown"
        reason = str(payload.get("reason", "")).lower() or "unknown"
        url = str(payload.get("url", ""))
        message = {
            "content": f"epicgames-freegames-node needs an action performed.\n{url}",
            "embeds": [
                {
                    "title": "Click to proceed",
                    "url": url,
                    "fields": [
                        {"name": "Account", "value": account},
                        {"name": "Reason", "value": reason},
                    ],
                }
            ],
        }
        try:
            post_to_discord(message)
        except Exception as exc:  # noqa: BLE001 - keep the relay alive
            print(f"discord-relay: post failed: {exc}", flush=True)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass  # loopback-only notifications, no need for access logs


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", LISTEN_PORT), Relay).serve_forever()
