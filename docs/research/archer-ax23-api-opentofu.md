---
type: Research Note
title: Archer AX23 v2 API & OpenTofu Feasibility
description: Protocol findings for the stock-firmware AX23 v2 (fw 1.11.x), existing integrations, and whether declarative OpenTofu management is worthwhile.
when: Read before building router automation, an OpenTofu provider, or any TP-Link integration for the home LAN.
resource: docs/research/archer-ax23-api-opentofu.md
tags: [research, router, tp-link, ax23, opentofu, terraform, api]
---

# Archer AX23 v2 — programmatic API & OpenTofu feasibility

Investigated 2026-10-25 against the live router. Read-only; no configuration
was modified.

## 1. Device identified

| Property | Value |
| --- | --- |
| Model | TP-Link Archer AX23 (AX1800) |
| Hardware revision | **v2** (`Archer AX23 v2.0` via authenticated firmware read) |
| Firmware | **1.1.2 Build 20250814 rel.14122(5553)** (authenticated `get_firmware`); the web UI build is 1.11.0 (`AX23v2_1.11.0_2025-08-14T01:47:53.298Z` in `<meta name="version">` of `/webpages/index.html` — handy unauthenticated firmware-build check) |
| Certification profile | `["US FCC", "SG CLS L1 STAGE2"]` (unauthenticated `device_config?form=config` read) |
| LAN address | `192.168.0.1`, gateway for `192.168.0.0/24` |
| Management interfaces | HTTP :80 (works), HTTPS :443 (serves a "Filtered Content" blocking page — local HTTPS management is disabled), LuCI CGI API under `/cgi-bin/luci/` |
| Operation mode | `router` (`login?form=sysmode` → `{"mode":"router"}`) |
| Factory default password | not in effect (`login?form=check_factory_default` → `is_default:false`) |

The UI build metadata is served in `<meta name="version">` of
`/webpages/index.html` — a handy unauthenticated firmware-version check.

Note: plain `curl` receives a 403 "Filtered Content" page on HTML routes even
with a perfect Chrome TLS fingerprint (`curl-impersonate`); the API CGI
endpoints do not filter. Local management is HTTP-only, which is normal for
this firmware generation but worth knowing for secret hygiene: the admin
password transits the LAN unencrypted on its way to the router.

## 2. The new-generation API protocol

The AX23 v2 runs the 2025-era Vue UI whose API is a JSON-over-form-POST RPC.
The protocol below was extracted from the router's own JS bundles (served at
`/webpages/js/`) and cross-checked against the
[`archer-router-mcp` AX53 auth-flow spec](https://github.com/ebenezer-isaac/archer-router-mcp/blob/main/docs/specs/archer-ax53-auth-flow.md)
and the [`tplinkrouterc6u` SG client](https://github.com/AlexandrErohin/TP-Link-Archer-C6U/blob/main/tplinkrouterc6u/client/sg.py).

- Every call: `POST http://192.168.0.1/cgi-bin/luci/;stok=<stok><path>?form=<form>`
- `Content-Type: application/x-www-form-urlencoded`
- Body is an `operation=...` form: `read`, `load`, `write`, `insert`
  (`new=<JSON>&index=<n>`), `update` (`key=<k>&new=<JSON>`), `remove`
  (`key=<k>&index=<n>`), `request`.
- Pre-login endpoints are never encrypted: `login?form=keys|auth|vercode`,
  `device_config?form=config`, `login?form=sysmode`,
  `login?form=check_factory_default`, `upgrade?form=info`, `locale?form=…`.
- This unit carries the **SG_L1_S2 certification**, so it uses the hardened
  variant (identical to Archer AX53 / BE3600 / BE230 on the same UI):
  1. `POST /login?form=keys` → RSA-2048 modulus+exponent for the password
     (`password: ["<512 hex>", "010001"]`).
  2. `POST /login?form=auth` → RSA key material for the session key exchange.
  3. Password: `SHA256("admin" + password)`; password itself RSA PKCS#1 v1.5;
     login payload AES-128-CBC; login request signed with RSA-OAEP.
  4. Every subsequent request: AES-128-CBC envelope + HMAC-SHA256 signature
     chunks; response AES-decrypted.
- Session: `stok` token in the URL + `sysauth` cookie; **one admin session
  total** — a second login evicts the first (the web UI) with HTTP 200
  `errorcode:"timeout"`.
- Failure modes to respect: error codes appear as `errorCode`, `errorcode`,
  `error`, or `error_code`; empty lists are `{}` not `[]`; roughly 12 failed
  logins trigger a ~2 h lockout; write responses don't validate unknown
  params — always read back after a write.

### Endpoint inventory (148 forms extracted from the UI JS)

Highlights, with the operations the UI itself uses:

| Area | Endpoint | Ops | Notes |
| --- | --- | --- | --- |
| Router status | `/admin/status?form=all` | read | WAN/LAN/clients summary |
| WAN/LAN status | `/admin/status?form=internet`, `router`, `wan_speed` | read | |
| DHCP server | `/admin/dhcps?form=setting` | read/write | enable, ranges, DNS |
| DHCP leases | `/admin/dhcps?form=client` | load | |
| **DHCP reservations** | `/admin/dhcps?form=reservation` | **load/insert/update/remove** | row identity = `key` |
| **Port forwarding** | `/admin/nat?form=vs` | **load/insert/update/remove** | virtual servers |
| Port triggering | `/admin/nat?form=pt` | load/insert/update/remove | |
| DMZ | `/admin/nat?form=dmz` | read/write | |
| ALG | `/admin/nat?form=alg` | read/write | per-protocol toggles |
| UPnP / NAT | `/admin/nat?form=setting` | read/write | |
| **IPv6 firewall rules** | `/admin/nat?form=fr6` | load/insert/update/remove | |
| Access control | `/admin/access_control?form=black_list`, `white_list`, `mode`, `enable` | read/write | per-device parental control, not a general firewall |
| Static routes | `/admin/network?form=routes_static`, `routes_system` | read (+write) | |
| LAN | `/admin/network?form=lan_fc` | read/write | IP, DHCP-announced DNS |
| WAN | `/admin/network?form=wan_fc` | read/write | connection type, DoH/DoT (`wan_dohdot`) |
| Wi-Fi (per band) | `/admin/wireless?form=wireless_2g|wireless_5g`, `guest_*` | read/write | SSID, security, channel, etc. |
| Wi-Fi features | `ofdma`, `twt`, `smart_connect`, `region` | read/write | |
| Devices | `/admin/smart_network?form=get_host_info`, `client_speed_limit`, `device_priority` | read/write | QoS per device |
| VPN | `/admin/vpn?form=wireguard`, `server`, `ovpn` | read/write | WireGuard server config |
| DDNS | `/admin/ddns?form=provider`, `dyndns`, `noip`, `tplink` | read/write | |
| Firmware | `/admin/firmware?form=config` | read/write | version + upgrade |
| Reboot | `/admin/system?form=reboot`, `/admin/reboot?form=set` | request/write | avoid |
| Logout | `/admin/system?form=logout` | request | free the single session |

Full list (re-derivable from `/webpages/js/*.js` with
`grep -hoE '"/[a-z_/]+\?form=[a-z_]+"'`):

<details><summary>All 148 endpoints</summary>

```
/admin/access_control?form=black_devices   /admin/access_control?form=black_list
/admin/access_control?form=enable          /admin/access_control?form=mode
/admin/access_control?form=white_devices   /admin/access_control?form=white_list
/admin/afc?form=settings                   /admin/cloud_account?form=auto_update_remind
/admin/cloud_account?form=check_device     /admin/cloud_account?form=check_internet
/admin/cloud_account?form=cloud_bind_status /admin/cloud_account?form=cloud_unbind
/admin/cloud_account?form=cloud_upgrade    /admin/cloud_account?form=detect_upgrade_status
/admin/cloud_account?form=get_deviceInfo   /admin/cloud_account?form=get_token
/admin/cloud_account?form=remind           /admin/cloud_account?form=user_login
/admin/cwmp?form=cwmp_setting              /admin/ddns?form=dyndns
/admin/ddns?form=noip                      /admin/ddns?form=provider
/admin/ddns?form=tplink                    /admin/dhcps?form=client
/admin/dhcps?form=reservation              /admin/dhcps?form=setting
/admin/diag?form=diag                      /admin/easymesh?form=easymesh_enable
/admin/easymesh_network?form=ap_avoidance_enable_status
/admin/easymesh_network?form=change_satellite
/admin/easymesh_network?form=get_mesh_device_list_all
/admin/easymesh_network?form=get_mesh_topo
/admin/easymesh_network?form=mesh_sclient_list_all
/admin/eco_mode?form=settings              /admin/ffs?form=config
/admin/firmware?form=auto_upgrade          /admin/firmware?form=config
/admin/firmware?form=config_multipart      /admin/firmware?form=save_upgrade
/admin/firmware?form=slave_cmd             /admin/firmware?form=upgrade
/admin/iot_security?form=enable            /admin/iot_security?form=isolated_devices_iot
/admin/iot_security?form=isolated_devices_main /admin/iot_security?form=isolated_list
/admin/iptv?form=setting                   /admin/iptv?form=udp_proxy_setting
/admin/ledgeneral?form=setting             /admin/ledpm?form=setting
/admin/nat?form=alg                        /admin/nat?form=client_list
/admin/nat?form=client_list_v6             /admin/nat?form=dmz
/admin/nat?form=fr6                        /admin/nat?form=pt
/admin/nat?form=setting                    /admin/nat?form=vs
/admin/network?form=lan_agg                /admin/network?form=lan_fc
/admin/network?form=mac_clone_advanced     /admin/network?form=port_speed_current
/admin/network?form=port_speed_supported   /admin/network?form=routes_static
/admin/network?form=routes_system          /admin/network?form=wan_autodetect
/admin/network?form=wan_detect_state       /admin/network?form=wan_dohdot
/admin/network?form=wan_fc                 /admin/network?form=wan_port_status
/admin/openvpn?form=config                 /admin/openvpn?form=export
/admin/openvpn?form=openvpn_cert           /admin/pptpd?form=accounts
/admin/pptpd?form=config                   /admin/privacy_policy?form=fing_auth_state
/admin/qos?form=update_database            /admin/quick_setup?form=ap_setup
/admin/quick_setup?form=check_router       /admin/quick_setup?form=quick_setup
/admin/quick_setup?form=re_setup           /admin/reboot?form=set
/admin/smart_network?form=client_speed_limit /admin/smart_network?form=device_priority
/admin/smart_network?form=game_accelerator /admin/smart_network?form=get_host_info
/admin/smart_network?form=patrol_devices   /admin/smart_network?form=patrol_enable
/admin/smart_network?form=patrol_insights  /admin/smart_network?form=patrol_limit
/admin/smart_network?form=patrol_owner_block /admin/smart_network?form=patrol_owner_list
/admin/smart_network?form=patrol_owner_website_block /admin/smart_network?form=qos
/admin/status?form=all                     /admin/status?form=cloud_login_window_pop
/admin/status?form=internet                /admin/status?form=menu_status
/admin/status?form=router                  /admin/status?form=wan_cable_match_stat
/admin/status?form=wan_dual_nat_state      /admin/status?form=wan_speed
/admin/syslog?form=save_log                /admin/system?form=logout
/admin/system?form=reboot                  /admin/system?form=sysmode
/admin/time?form=dst                       /admin/usbmodem?form=isplist
/admin/usbmodem?form=modemset              /admin/vpn?form=enable
/admin/vpn?form=ovpn                       /admin/vpn?form=server
/admin/vpn?form=thirdvpn                   /admin/vpn?form=vpn_user_devices
/admin/vpn?form=vpn_user_list              /admin/vpn?form=wireguard
/admin/wifidog?form=portal_background      /admin/wifidog?form=portal_logo
/admin/wireguard?form=account              /admin/wireguard?form=config
/admin/wireless?form=ofdma                 /admin/wireless?form=ofdma_mimo
/admin/wireless?form=portal_content        /admin/wireless?form=region
/admin/wireless?form=smart_connect         /admin/wireless?form=twt
/admin/wireless?form=wireless              /admin/wireless?form=wireless_addition_setting
/blocking?form=vercode                     /debug?form=cmd
/debug?form=refresh                        /debug?form=upload
/device_config?form=config                 /domain_login?form=dlogin
/domain_redirect?form=get                  /locale?form=country
/locale?form=lang                          /locale?form=list
/locale?form=multilang                     /login?form=auth
/login?form=check_factory_default          /login?form=check_internet
/login?form=cloud_bind_status              /login?form=cloud_login
/login?form=get_deviceInfo                 /login?form=get_eweb_url
/login?form=get_firmware_info              /login?form=get_token
/login?form=initial_login                  /login?form=keys
/login?form=login                          /login?form=password
/login?form=sysmode                        /login?form=vercode
/upgrade?form=info                         /upgrade?form=set
/wan_error?form=never                      /wan_error?form=read
```

</details>

## 3. Existing integrations

Researched 2026-10-25 (status, dates, and support matrices verified against
GitHub/PyPI). The task's starting URLs contained one dead end:
`marckregio/TP-Link-Archer-C6` is a 0★ fork of the real project.

| Project | Status | AX23 v2 / fw 1.11.x verdict |
| --- | --- | --- |
| [`AlexandrErohin/TP-Link-Archer-C6U`](https://github.com/AlexandrErohin/TP-Link-Archer-C6U) (`tplinkrouterc6u` on PyPI, GPL-3.0) | very active, v5.37.0 (2026-10-17) | **Expected to work**: its `TplinkRouterSG` client implements exactly this unit's protocol (SHA256 + RSA-2048 + OAEP + HMAC), proven on AX53 with the same 1.11.0 UI; AX23 v1.0/v1.2 are on the supported list, v2 is unlisted. Read: firmware, status, WAN, DHCP leases + reservations, Wi-Fi. Write: reservations, Wi-Fi, VPN, DHCP server. **No port-forwarding API** — but the generic `request()` reaches `admin/nat?form=vs`. |
| [`AlexandrErohin/home-assistant-tplink-router`](https://github.com/AlexandrErohin/home-assistant-tplink-router) (HACS custom, MIT) | very active, v2.44.0 (2026-10-17) | Same engine as above (pins `tplinkrouterc6u==5.37.0`). Device trackers, sensors, reboot button, reservation services. |
| [`sharozdawa/tplink-archer-mcp`](https://github.com/sharozdawa/tplink-archer-mcp) (MIT) | stale since 2026-05, 2★ | Claims AX23 "should work" (untested); drives the **Vue UI in headless Chromium** — unsuitable for Terraform, but its docs confirm the callback-registry restrictions. |
| [`iambalaji-k/tplink-router-api`](https://github.com/iambalaji-k/tplink-router-api) (MIT) | new, active (2026-10) | AX12 (1024-bit RSA era) — protocol writeups transfer, code targets an older auth generation. Its 226-endpoint survey and gotcha list are valuable. |
| [`lucavb/terraform-provider-tplink-easysmart`](https://github.com/lucavb/terraform-provider-tplink-easysmart) (MIT) | active-ish | **Switch-only** (TL-SG108PE family). Confirmed irrelevant for the router, but an excellent terraform-plugin-framework skeleton to clone. |
| HA core `tplink_router` | — | **Does not exist** (researched: not in `home-assistant/components`, docs page 404s). The HACS custom component above is the de-facto integration. |
| [`ebenezer-isaac/archer-router-mcp`](https://github.com/ebenezer-isaac/archer-router-mcp) (MIT) | active (2026-10-20) | Best protocol documentation anywhere: AX53 UI 1.11.0 auth flow with byte-exact test vectors. Directly applicable to this unit. |
| [`chang196700/terraform-provider-tplinkrouter`](https://github.com/chang196700/terraform-provider-tplinkrouter) | new (2026-10) | Only router Terraform provider found — targets TL-ER6220T business routers via SLP; not compatible. **No provider exists for TP-Link home routers.** |

## 4. Live read-only verification (tplinkrouterc6u 5.37.0, SG path)

Verified 2026-10-25 with `TplinkRouterSG` over HTTP, one login per run, logout
afterwards, zero failed logins (no lockout exposure). Password supplied via
environment; nothing sensitive in transcript or output. The probe script is
[`archer-ax23-probe.py`](archer-ax23-probe.py) (sanitizes passphrases and WAN
addresses; read operations only).

| Operation | Result |
| --- | --- |
| Login (SG: SHA256 + RSA-2048 + OAEP + HMAC-SHA256 + AES-CBC) | **works** — AX23 v2 fw 1.1.2 is on the same hardened protocol as AX53/BE-series |
| Firmware / hardware info | **works** — `Archer AX23 v2.0`, `1.1.2 Build 20250814 rel.14122(5553)` |
| Router status | **works** (raw `admin/status?form=all` read: WAN state, DNS, CPU/mem, client lists, uptime). The library's typed `get_status()` parser hit a field quirk — use the raw read for data sources |
| WAN/LAN config | **works** — WAN DHCP /24, DNS pair, LAN `192.168.0.1/24` |
| DHCP leases | **works** — 7 leases read via `admin/dhcps?form=client` |
| DHCP reservations | **works** — 12 reservations read via `admin/dhcps?form=reservation` |
| Wi-Fi config (2.4/5 GHz, guest, IoT) | **works** — SSID, encryption (`psk_sae`), channel, MAC, hidden/enable flags; passphrases redacted client-side |
| Port forwarding (`admin/nat?form=vs`) | **works** — 2 rules read; row shape `{name, ipaddr, external_port, internal_port, protocol, enable}`; insert/update/remove verbs confirmed in UI JS |
| Port triggering (`form=pt`), IPv6 firewall (`form=fr6`) | **works** — empty tables returned (`{}`) |
| DMZ, ALG, NAT/UPnP setting, DHCP server setting, Smart Connect | **works** |
| Static routes (`admin/network?form=routes_static`) | **failed** — encrypted error response despite the form existing in the UI JS; needs a follow-up with the exact op the UI uses |

Untested (writes): reservation add/delete, port-forward CRUD, Wi-Fi writes —
deliberately not exercised. Wire formats for writes are documented in the
endpoint table above and in the SG client source.

## 5. OpenTofu suitability

The API's shape is unusually provider-friendly:

- **Stable row identity**: table resources (DHCP reservations, port forwards,
  IPv6 firewall rules) address rows by `key` + `index` with full CRUD verbs —
  directly mappable to Terraform resources with import support.
- **Scalar resources** (DHCP server, DMZ, ALG, LAN, WAN, Wi-Fi per band) are
  read/write — mappable with read-back-after-write drift detection.
- **Read-only inventory** (status, leases, devices, firmware) maps to data
  sources.
- Sessions are stateful (`stok`+cookie, single admin session, lockout risk) —
  the provider must serialize access (one login per apply), log out, and never
  retry failed logins blindly.

| Resource | API | Terraform mapping | Value |
| --- | --- | --- | --- |
| DHCP reservations | CRUD + key | resource | High |
| Port-forwarding rules | CRUD + key | resource | High |
| IPv6 firewall rules | CRUD + key | resource | High |
| DMZ / ALG / UPnP | read/write | resource (scalar) | Medium |
| DHCP server / LAN DNS | read/write | resource (scalar) | Medium |
| Wi-Fi SSID/security | read/write | resource (scalar) | Medium |
| Static routes | read (+write) | resource | Medium |
| Device inventory | read | data source | Medium |
| Router status / firmware | read | data source | Medium |

## 6. Recommendation

1. **Reuse `tplinkrouterc6u` (option B/C)**: it already implements this exact
   auth protocol; DHCP-reservation CRUD exists upstream; port-forwarding needs
   a small upstream contribution using `admin/nat?form=vs` (wire format
   documented above). Extending the actively-maintained library benefits other
   users and keeps the protocol knowledge in one place.
2. **Provider later, data sources first** (option A only after step 1 lands):
   clone the `lucavb/tplink-easysmart` plugin-framework skeleton; start with
   data sources (status, firmware, device list) + `tplink_ax23_reservation`
   and `tplink_ax23_port_forward` resources behind an explicit
   enablement flag. Host it in its own repository, not inside `repparw/nix`.
3. **Short term**: the read-only probe script (this investigation) can feed a
   monitoring/inventory view (e.g. Home Assistant or a cron + Prometheus
   exporter) without any writes.

## 7. Risks & limitations

- **Single admin session**: any automation login evicts the human's web UI
  session (and vice versa). Terraform applies will kick you out of the web UI.
- **Lockout**: ~12 failed logins ≈ 2 h lockout — the provider must never
  brute-force; store credentials in env/secret manager, not state.
- **Firmware dependence**: TP-Link changed the auth scheme at least three
  times across recent firmwares (classic → SG → simplified); every firmware
  upgrade can break the client. The certification probe (`device_config`) is
  the correct auto-detect hook.
- **HTTP-only local management**: the admin password traverses the LAN in
  cleartext inside the login flow (its confidentiality rests on RSA, but
  request/response metadata is visible). Do not expose management to untrusted
  LAN segments.
- **Watchdog**: rapid-fire request storms can watchdog-reboot similar units
  (BE400 reports); pace requests.
- Upstream library is GPL-3.0 — keep any Go provider (own repo, MPL/Apache)
  talking to a separate process or reimplementing the protocol, not importing
  the Python code.

## Related

- [Host profiles](../hosts.md) — LAN topology around 192.168.0.1
- [Secret inventory](../architecture/secret-inventory.md) — where router
  credentials should live (sops-nix, not Terraform state)
