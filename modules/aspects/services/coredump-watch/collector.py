"""Collect bounded crash metadata and retry durable deliveries to Hermes."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

MESSAGE_ID = 'fc2e22bc6ee647b6b90729ab34a250b1'
FIELDS = 'COREDUMP_EXE,COREDUMP_SIGNAL,COREDUMP_PID,COREDUMP_UID,COREDUMP_UNIT,COREDUMP_USER_UNIT,COREDUMP_TIMESTAMP,_BOOT_ID'


def atomic_json(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(value, handle, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def frame_signature(text):
    frames = []
    for line in text.splitlines():
        match = re.search(r'#\d+\s+(?:0x[0-9a-f]+\s+)?(.+)', line)
        if match:
            frame = re.sub(r'\s*\+\s*0x[0-9a-f]+', '', match[1])
            frame = re.sub(r'0x[0-9a-f]+', '<address>', frame)
            frames.append(frame[:240])
        if len(frames) == 12:
            break
    return '\n'.join(frames)[:3000]


def event_from(entry, host, frames):
    executable = entry['COREDUMP_EXE']
    if not isinstance(executable, str) or not executable.startswith('/') or len(executable) > 1024:
        raise ValueError('invalid executable')
    if any(ord(c) < 32 for c in executable):
        raise ValueError('invalid executable')
    event = dict(schema_version=1, host=host, boot_id=entry['_BOOT_ID'],
                 timestamp_us=int(entry['COREDUMP_TIMESTAMP']), pid=int(entry['COREDUMP_PID']),
                 uid=int(entry['COREDUMP_UID']), executable=executable,
                 signal=int(entry['COREDUMP_SIGNAL']), unit=entry.get('COREDUMP_USER_UNIT') or entry.get('COREDUMP_UNIT', ''),
                 count=1, frame_signature=frames)
    identity = [host, event['boot_id'], event['timestamp_us'], event['pid'], executable]
    event['event_id'] = hashlib.sha256(json.dumps(identity, separators=(',', ':')).encode()).hexdigest()
    return event


def collect(state, host, muted):
    cursor_file = state / 'coredumps-cursor.json'
    cursor = json.loads(cursor_file.read_text()) if cursor_file.exists() else None
    command = ['journalctl', '--no-pager', '-o', 'json', f'MESSAGE_ID={MESSAGE_ID}', f'--output-fields={FIELDS}']
    command += [f"--after-cursor={cursor['cursor']}"] if cursor else ['--since=-24h']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    count = 0
    try:
        for line in process.stdout:
            entry = json.loads(line)
            if Path(entry.get('COREDUMP_EXE', '')).name not in muted:
                # Select this occurrence, not another process that reused the PID.
                info = subprocess.run(['coredumpctl', '--no-pager', 'info', f"COREDUMP_PID={entry.get('COREDUMP_PID', '')}",
                                       f"_BOOT_ID={entry.get('_BOOT_ID', '')}",
                                       f"COREDUMP_TIMESTAMP={entry.get('COREDUMP_TIMESTAMP', '')}"],
                                      capture_output=True, text=True, timeout=30)
                try:
                    event = event_from(entry, host, frame_signature(info.stdout))
                except (KeyError, ValueError, TypeError):
                    # A malformed journal record cannot inject text into the model.
                    print('coredumps: skipped incomplete metadata')
                else:
                    name = event['event_id'] + '.json'
                    pending = state / 'coredumps-outbox' / name
                    if not pending.exists() and not (state / 'coredumps-seen' / name).exists():
                        atomic_json(pending, event)
            # Durable local spool is the commit point; delivery retries independently.
            atomic_json(cursor_file, dict(cursor=entry['__CURSOR']))
            count += 1
            if count == 128:
                process.terminate()
                break
        result = process.wait(timeout=10)
        if result and count < 128:
            # Vacuumed cursors are retried with an overlapping bounded baseline.
            if cursor:
                cursor_file.unlink(missing_ok=True)
            raise RuntimeError('journal query failed; retry on next run')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def deliver(outbox, target, identity):
    delivered = 0
    for path in sorted(outbox.glob('*.json'))[:128]:
        event = json.loads(path.read_text())
        result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'IdentityAgent=none',
                                 '-o', 'ConnectTimeout=15', '-i', identity, target,
                                 '/run/current-system/sw/bin/hermes-crash-ingest'],
                                input=path.read_text(), capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError('Hermes intake unavailable; retained crash outbox')
        try:
            acknowledged = json.loads(result.stdout)['event_id'] == event['event_id']
        except (ValueError, KeyError, TypeError):
            acknowledged = False
        if not acknowledged:
            raise RuntimeError('Hermes intake ACK mismatch; retained crash outbox')
        atomic_json(outbox.parent / 'coredumps-seen' / path.name, event['timestamp_us'])
        path.unlink()
        delivered += 1
    print(f'coredumps: delivered {delivered}, pending {len(list(outbox.glob("*.json")))}')


def main():
    os.umask(0o077)
    state = Path(os.environ.get('STATE_DIRECTORY', '/var/lib/fleet-health'))
    state.mkdir(parents=True, exist_ok=True)
    outbox = state / 'coredumps-outbox'
    outbox.mkdir(mode=0o700, exist_ok=True)
    (state / 'coredumps-seen').mkdir(mode=0o700, exist_ok=True)
    with (state / 'coredumps.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        collect(state, os.environ['HOSTNAME'], json.loads(os.environ.get('MUTE_JSON', '[]')))
        deliver(outbox, os.environ['HERMES_TARGET'], os.environ['HERMES_SSH_IDENTITY'])


if __name__ == '__main__':
    main()
