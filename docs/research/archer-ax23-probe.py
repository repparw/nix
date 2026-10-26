#!/usr/bin/env python3
"""Read-only probe for TP-Link Archer AX23 v2 (firmware 1.11.x, SG_L1_S2 auth).

Uses tplinkrouterc6u (TplinkRouterSG) to authenticate and read status/config.
All output is sanitized: Wi-Fi passphrases and WAN address are redacted before
printing. No write operations are performed.

Env:
  TPLINK_HOST      router address (default http://192.168.0.1)
  TPLINK_PASSWORD  admin password (required)

Requires: python3 with the `tplinkrouterc6u` package (>= 5.33 for the SG
client). Run against the router with the admin password in the environment;
all output is sanitized (passphrases and WAN addresses redacted). The script
performs exactly one login, read-only queries, and a logout."""
import json
import os
import sys

from tplinkrouterc6u import TplinkRouterSG

SECRET_KEYS = {"password", "passwd", "passphrase", "psk_key", "psk_cipher",
               "psk_version", "wep_key1", "wep_key2", "wep_key3", "wep_key4",
               "wpa_key", "guest_2g_psk_key", "guest_5g_psk_key",
               "guest_2g5g_psk_key", "iot_2g_psk_key", "iot_5g_psk_key",
               "mlo_host_2g_psk_key", "mlo_host_5g_psk_key"}
WAN_KEYS = {"wan_ipv4_ipaddr", "wan_ipv4_gateway", "wan_macaddr",
            "wan_ipv6_ip6addr", "modem_ipaddr", "modem_gateway"}


def sanitize(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k in SECRET_KEYS:
                out[k] = "***REDACTED***" if v else v
            elif k in WAN_KEYS:
                out[k] = "***WAN***" if v else v
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(v) for v in obj]
    return obj


def main():
    host = os.environ.get("TPLINK_HOST", "http://192.168.0.1")
    password = os.environ.get("TPLINK_PASSWORD")
    if not password:
        print("TPLINK_PASSWORD not set", file=sys.stderr)
        return 2

    router = TplinkRouterSG(host, password)
    report = {}
    try:
        router.authorize()
        report["auth"] = "ok (TplinkRouterSG: SHA256 + RSA-2048 + HMAC-SHA256 + AES-CBC)"

        try:
            fw = router.get_firmware()
            report["firmware"] = {"model": fw.model,
                                  "hardware_version": fw.hardware_version,
                                  "firmware_version": fw.firmware_version}
        except Exception as e:
            report["firmware"] = f"error: {e}"

        try:
            st = router.get_status()
            report["status"] = {
                "conn_type": st.conn_type,
                "wan_ipv4_uptime": st.wan_ipv4_uptime,
                "cpu_usage": st.cpu_usage,
                "mem_usage": st.mem_usage,
                "clients_total": st.clients_total,
                "wired_total": st.wired_total,
                "wifi_clients_total": st.wifi_clients_total,
                "lan_dhcp_enabled": st.lan_ipv4_dhcp_enable,
                "wifi_2g_enable": st.wifi_2g_enable,
                "wifi_5g_enable": st.wifi_5g_enable,
                "iot_2g_enable": st.iot_2g_enable,
                "guest_2g_enable": st.guest_2g_enable,
                "devices": [
                    {"hostname": d.hostname, "ip": str(d.ipaddr), "mac": str(d.macaddr),
                     "type": str(d.type), "active": d.active}
                    for d in (st.devices or [])
                ],
            }
        except Exception as e:
            report["status"] = f"error: {e}"

        try:
            wan = router.get_ipv4_status()
            report["wan_ipv4"] = {
                "conn_type": wan.wan_ipv4_conntype,
                "netmask": str(wan.wan_ipv4_netmask),
                "primary_dns": str(wan.wan_ipv4_pridns),
                "secondary_dns": str(wan.wan_ipv4_snddns),
                "remote": wan.remote,
            }
        except Exception as e:
            report["wan_ipv4"] = f"error: {e}"

        try:
            leases = router.get_ipv4_dhcp_leases()
            report["dhcp_leases"] = [
                {"hostname": l.hostname, "ip": str(l.ipaddr), "mac": str(l.macaddr),
                 "lease_time": l.lease_time} for l in leases]
        except Exception as e:
            report["dhcp_leases"] = f"error: {e}"

        try:
            res = router.get_ipv4_reservations()
            report["dhcp_reservations"] = [
                {"hostname": r.hostname, "ip": str(r.ipaddr), "mac": str(r.macaddr),
                 "enabled": r.enabled} for r in res]
        except Exception as e:
            report["dhcp_reservations"] = f"error: {e}"

        for wifi_name in ["HOST_2G", "HOST_5G"]:
            try:
                from tplinkrouterc6u import Connection
                w = router.get_wifi(Connection[wifi_name])
                report[f"wifi_{wifi_name}"] = {
                    "ssid": w.ssid, "enable": w.enable,
                    "hidden": w.hidden, "encryption": w.encryption,
                    "channel": getattr(w, "channel", None),
                    "hwmode": getattr(w, "hwmode", None),
                    "macaddr": str(getattr(w, "macaddr", "")),
                }
            except Exception as e:
                report[f"wifi_{wifi_name}"] = f"error: {e}"

        # Low-level reads the library does not natively expose (read verbs only).
        # Table forms (routes, vs, pt, fr6) require operation=load, not read.
        for label, path, op in [
            ("port_forwarding_vs", "/admin/nat?form=vs", "load"),
            ("port_triggering_pt", "/admin/nat?form=pt", "load"),
            ("ipv6_firewall_fr6", "/admin/nat?form=fr6", "load"),
            ("dmz", "/admin/nat?form=dmz", "read"),
            ("alg", "/admin/nat?form=alg", "read"),
            ("nat_setting", "/admin/nat?form=setting", "read"),
            ("dhcp_setting", "/admin/dhcps?form=setting", "read"),
            ("lan_setting", "/admin/network?form=lan_fc", "read"),
            ("static_routes", "/admin/network?form=routes_static", "load"),
            ("system_routes", "/admin/network?form=routes_system", "load"),
            ("smart_connect", "/admin/wireless?form=smart_connect", "read"),
        ]:
            try:
                data = router.request(path, "operation=" + op)
                report[label] = sanitize(data)
            except Exception as e:
                report[label] = f"error: {e}"
    finally:
        try:
            router.logout()
        except Exception:
            pass

    out = json.dumps(report, indent=2, default=str)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
