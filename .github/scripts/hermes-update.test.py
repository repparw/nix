#!/usr/bin/env python3
"""Regression checks for the Hermes stable-release update workflow."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/hermes-update.yml"


def shell_script():
    payload = WORKFLOW.read_text().partition("        run: |\n")[2]
    if not payload:
        raise AssertionError("Hermes workflow has no executable shell step")
    return textwrap.dedent(payload)


def function(name):
    match = re.search(rf"(?ms)^{re.escape(name)}\(\) \{{\n.*?^\}}", shell_script())
    if not match:
        raise AssertionError(f"missing {name} in Hermes updater")
    return match.group()


def bash(script, *, cwd=None, env=None):
    return subprocess.run(
        ["bash", "-c", "set -euo pipefail\n" + script],
        cwd=cwd, env={**os.environ, **(env or {})},
        text=True, capture_output=True,
    )


class HermesUpdateTests(unittest.TestCase):
    def test_workflow_bash_syntax(self):
        result = subprocess.run(["bash", "-n", "-c", shell_script()], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_version_format(self):
        check = function("is_valid_version")
        for tag in ("v0.22.5", "v1.0.0", "v20.123.456"):
            result = bash(check + f"\nis_valid_version '{tag}'")
            self.assertEqual(result.returncode, 0, (tag, result.stderr))
        for tag in ("v1", "1.2.3", "v01.2.3", "v1.2", "v1.2.3.4", "v1.2.3-rc1"):
            result = bash(check + f"\nis_valid_version '{tag}'")
            self.assertNotEqual(result.returncode, 0, tag)

    def test_release_ordering(self):
        # The same sort -V comparison used before branch publication.
        for current, latest, allowed in (
            ("v0.22.5", "v0.22.6", True),
            ("v0.9.9", "v0.10.0", True),
            ("v1.0.0", "v1.0.0", True),
            ("v1.2.3", "v1.2.2", False),
            ("v2.0.0", "v1.99.99", False),
        ):
            result = bash(
                'test "$(printf \'%s\\n\' "$CURRENT" "$LATEST" | sort -V | tail -n 1)" = "$LATEST"',
                env={"CURRENT": current, "LATEST": latest},
            )
            self.assertEqual(result.returncode == 0, allowed, (current, latest))

    def test_validation_recovery(self):
        prepare = function("prepare_run")
        scenarios = [
            ("", "", False),
            ("31\tcompleted\tsuccess", "", False),
            ("31\tin_progress\t", "", False),
            ("31\tcompleted\tfailure", "31", True),
        ]
        for row, ignored, dispatch in scenarios:
            with self.subTest(row=row), tempfile.TemporaryDirectory() as d:
                calls = Path(d) / "calls"
                script = "\n".join((
                    prepare,
                    'latest_run() { printf "%s\\n" "$ROW"; }',
                    'gh() { printf "%s\\n" "$*" >> "$CALLS"; }',
                    'pr=777',
                    'prepare_run ci.yml automation/hermes-stable abc123',
                ))
                result = bash(script, env={"ROW": row, "CALLS": str(calls)})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), ignored)
                self.assertEqual(calls.exists(), dispatch)
                if dispatch:
                    self.assertIn("hermes_update=true", calls.read_text())
                    self.assertIn("expected_sha=abc123", calls.read_text())

    def test_wait_ignores_failed_previous_run(self):
        with tempfile.TemporaryDirectory() as d:
            counter = Path(d) / "counter"
            script = "\n".join((
                function("wait_for_run"),
                'latest_run() {',
                '  local n=0',
                '  if [ -f "$COUNTER" ]; then n=$(cat "$COUNTER"); fi',
                '  n=$((n+1)); printf "%s" "$n" > "$COUNTER"',
                '  if [ "$n" = 1 ]; then printf "31\\tcompleted\\tfailure\\n";',
                '  elif [ "$n" = 2 ]; then printf "32\\tin_progress\\t\\n";',
                '  else printf "32\\tcompleted\\tsuccess\\n"; fi',
                '}',
                'sleep() { :; }',
                'poll_seconds=0; poll_attempts=5',
                'wait_for_run ci.yml automation/hermes-stable abc123 31',
            ))
            result = bash(script, env={"COUNTER": str(counter)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "32")

    def test_tip_ownership_rejects_human_modification(self):
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)
            def git(*args, env=None):
                result = subprocess.run(["git", *args], cwd=work, env={**os.environ, **(env or {})},
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout.strip()

            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            (work / "modules/hosts").mkdir(parents=True)
            def populate(tag):
                for f in ("flake.nix", "modules/hosts/epsilon.nix"):
                    (work / f).write_text('url = "github:NousResearch/hermes-agent/' + tag + '";\n')
                (work / "flake.lock").write_text(
                    '{"nodes":{"hermes-agent":{"original":{"ref":"' + tag + '"}}}}\n')
            populate("v0.22.5")
            git("add", ".")
            git("commit", "-qm", "baseline")
            populate("v0.22.6")
            git("add", ".")
            bot = "41898282+github-actions[bot]@users.noreply.github.com"
            git("commit", "-qm", "chore(hermes): update to v0.22.6",
                env={"GIT_AUTHOR_NAME": "github-actions[bot]", "GIT_AUTHOR_EMAIL": bot})
            tip = git("rev-parse", "HEAD")
            git("remote", "add", "origin", str(work))
            verify = function("verify_managed_tip")
            valid = bash(verify + f"\nverify_managed_tip '{tip}'", cwd=work)
            self.assertEqual(valid.returncode, 0, valid.stderr)
            (work / "modules/hosts/epsilon.nix").write_text(
                'url = "github:NousResearch/hermes-agent/v0.22.6";\n# human edit\n')
            git("add", ".")
            git("commit", "-qm", "human modification")
            edited = git("rev-parse", "HEAD")
            modified = bash(verify + f"\nverify_managed_tip '{edited}'", cwd=work)
            self.assertNotEqual(modified.returncode, 0)

    def test_exact_sha_validation_wiring(self):
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        validation = (ROOT / ".github/workflows/revision-validation.yml").read_text()
        self.assertIn("-f hermes_update=true", shell_script())
        self.assertIn("hermes_update:", ci)
        self.assertIn("hermes_update:", validation)
        self.assertIn("hermes-package-build:", validation)
        self.assertIn("nixosConfigurations.epsilon.config.containers.hermes.config.services.hermes-agent.package", validation)
        self.assertIn('test "$HERMES_RESULT" = success', validation)


if __name__ == "__main__":
    unittest.main()
