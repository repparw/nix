"""Ensure adb is connected to the phone and print the reachable address.

Order of attempts:
1. the cached address, if it still answers
2. reconnect to the cached address (covers an adb server restart)
3. mDNS discovery, for when the phone picked a new port
4. the legacy tcpip port

mDNS only answers while the phone is awake, so the cache carries the common
case: the phone keeps its wireless debugging port across a host reboot, and
only changes it when wireless debugging is toggled or Android reboots.
"""

import argparse
import os
import socket
import struct
import subprocess
import sys
import time

DEFAULT_IP = "192.168.0.32"
FALLBACK_PORTS = (5555,)
SERVICE = "_adb-tls-connect._tcp.local"
MULTICAST = "224.0.0.251"
MDNS_PORT = 5353
PROBE_TIMEOUT = 5
CONNECT_TIMEOUT = 6

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "phone-connect",
)
CACHE_FILE = os.path.join(STATE_DIR, "address")


def adb(args, timeout):
    try:
        return subprocess.run(
            ["adb", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None
    except FileNotFoundError:
        sys.exit("phone-connect: adb not found in PATH")


def probe(address, attempts=3):
    for attempt in range(attempts):
        result = adb(["-s", address, "shell", "true"], PROBE_TIMEOUT)
        if result is not None and result.returncode == 0:
            return True
        if attempt + 1 < attempts:
            time.sleep(0.5)
    return False


def connect(address):
    if ":" not in address:
        return False
    adb(["connect", address], CONNECT_TIMEOUT)
    return probe(address)


def existing_transport():
    """Return a transport adb already holds for the phone, whatever its address."""
    result = adb(["devices", "-l"], 5)
    if result is None or result.returncode != 0:
        return None
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 2 or fields[1] != "device":
            continue
        address = fields[0]
        if DEFAULT_IP in address or "SM_S918B" in line:
            if probe(address, attempts=1):
                return address
    return None


def read_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as handle:
            address = handle.read().strip()
    except OSError:
        return None
    return address or None


def write_cache(address):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as handle:
            handle.write(address + "\n")
    except OSError:
        pass


def encode_name(name):
    encoded = b""
    for label in name.split("."):
        if label:
            encoded += bytes([len(label)]) + label.encode()
    return encoded + b"\x00"


def read_name(data, offset):
    labels = []
    jumped = False
    end = None
    while True:
        length = data[offset]
        if length == 0:
            offset += 1
            break
        if length & 0xC0 == 0xC0:
            if not jumped:
                end = offset + 2
            jumped = True
            offset = struct.unpack("!H", data[offset : offset + 2])[0] & 0x3FFF
            continue
        labels.append(data[offset + 1 : offset + 1 + length].decode("utf-8", "replace"))
        offset += 1 + length
    return ".".join(labels), (end if jumped else offset)


def mdns_lookup(timeout=3.0):
    """Ask the LAN where the phone's wireless debugging port is."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
        sock.bind(("", MDNS_PORT))
    except OSError:
        sock.close()
        return None

    try:
        route = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            route.connect((DEFAULT_IP, 9))
            interface = route.getsockname()[0]
        except OSError:
            interface = None
        finally:
            route.close()

        if interface:
            membership = struct.pack(
                "4s4s", socket.inet_aton(MULTICAST), socket.inet_aton(interface)
            )
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
            sock.setsockopt(
                socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(interface)
            )

        query = (
            struct.pack("!HHHHHH", 0, 0, 1, 0, 0, 0)
            + encode_name(SERVICE)
            + struct.pack("!HH", 12, 1)
        )
        sock.sendto(query, (MULTICAST, MDNS_PORT))
        sock.settimeout(0.5)

        port = None
        target = None
        address = None
        deadline = time.time() + timeout
        while time.time() < deadline and not (port and address):
            try:
                data, source = sock.recvfrom(9000)
            except (socket.timeout, OSError):
                continue
            try:
                questions, answers, authority, additional = struct.unpack(
                    "!4H", data[4:12]
                )
                offset = 12
                for _ in range(questions):
                    _, offset = read_name(data, offset)
                    offset += 4
                for _ in range(answers + authority + additional):
                    name, offset = read_name(data, offset)
                    rtype, _, _, rdlength = struct.unpack(
                        "!HHIH", data[offset : offset + 10]
                    )
                    offset += 10
                    if rtype == 33 and "_adb" in name:
                        target, _ = read_name(data, offset + 6)
                        port = struct.unpack("!H", data[offset + 4 : offset + 6])[0]
                    elif rtype == 1 and target and name == target:
                        address = socket.inet_ntoa(data[offset : offset + rdlength])
                    offset += rdlength
            except (IndexError, struct.error, ValueError):
                continue
    finally:
        sock.close()

    if port and address:
        return f"{address}:{port}"
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Ensure adb is connected to the phone and print IP:PORT."
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="no diagnostics, always exit 0, for timers",
    )
    args = parser.parse_args()

    def fail(message):
        if not args.quiet:
            print(message, file=sys.stderr)
        return 0 if args.quiet else 1

    live = existing_transport()
    if live:
        write_cache(live)
        print(live)
        return 0

    cached = read_cache()
    if cached and probe(cached):
        print(cached)
        return 0

    if cached and connect(cached):
        write_cache(cached)
        print(cached)
        return 0

    discovered = mdns_lookup()
    if discovered and connect(discovered):
        write_cache(discovered)
        print(discovered)
        return 0

    host = (cached or DEFAULT_IP).split(":")[0]
    for port in FALLBACK_PORTS:
        address = f"{host}:{port}"
        if connect(address):
            write_cache(address)
            print(address)
            return 0

    return fail("phone-connect: phone not reachable")


if __name__ == "__main__":
    sys.exit(main())
