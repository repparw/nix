#!/usr/bin/env python3
"""Fixtures for check-agent-docs.py.

Runs the validator against temporary repositories that each carry one known
defect, then against a real repository root (passed as the first argument or
via AGENT_DOCS_ROOT) to prove the repaired tree passes.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check-agent-docs.py")
_spec = importlib.util.spec_from_file_location("check_agent_docs", MODULE_PATH)
assert _spec and _spec.loader
check_agent_docs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_agent_docs)

VALID_PAGE = """\
---
type: Runbook
title: Example
description: An example page.
when: Read when testing.
resource: README.md
tags: [test]
---

# Example

See [the index](../index.md).
"""

VALID_INDEX = """\
---
type: Documentation Index
title: Docs
description: Test index.
when: Read when navigating.
resource: README.md
tags: [test]
---

# Docs

- [Example](runbooks/example.md)
"""


class ValidatorFixtures(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "AGENTS.md").write_text("# Agents\n", encoding="utf-8")
        (self.root / "README.md").write_text("# Readme\n", encoding="utf-8")

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, rel: str, text: str):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_valid_fixture_passes(self):
        self.write("docs/runbooks/example.md", VALID_PAGE)
        self.write("docs/index.md", VALID_INDEX)
        self.assertEqual([], check_agent_docs.validate_tree(self.root))

    def test_nul_bytes_rejected(self):
        (self.root / "docs").mkdir()
        (self.root / "docs" / "bad.md").write_bytes(b"# Bad\x00\n")
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("NUL" in error for error in errors), errors)

    def test_malformed_yaml_rejected(self):
        self.write(
            "docs/bad.md",
            "---\ntype: Runbook\ntitle: Issue Tracker: GitHub\ndescription: d\n"
            "when: w\nresource: README.md\ntags: [test]\n---\n",
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("not valid YAML" in error for error in errors), errors)

    def test_quoted_title_accepted(self):
        self.write(
            "docs/ok.md",
            '---\ntype: Agent Guide\ntitle: "Issue Tracker: GitHub"\n'
            "description: d\nwhen: w\ntags: [test]\n---\n",
        )
        self.assertEqual([], check_agent_docs.validate_tree(self.root))

    def test_broken_relative_link_rejected(self):
        self.write(
            "docs/runbooks/example.md",
            VALID_PAGE.replace("index.md", "missing.md"),
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("broken relative link" in error for error in errors), errors)

    def test_missing_required_field_rejected(self):
        self.write(
            "docs/runbooks/example.md",
            VALID_PAGE.replace("when: Read when testing.\n", ""),
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("`when`" in error for error in errors), errors)

    def test_missing_resource_rejected(self):
        self.write(
            "docs/runbooks/example.md",
            VALID_PAGE.replace("resource: README.md\n", ""),
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("`resource`" in error for error in errors), errors)

    def test_unknown_resource_rejected(self):
        self.write(
            "docs/runbooks/example.md",
            VALID_PAGE.replace("resource: README.md", "resource: nowhere.nix"),
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("resource" in error and "nowhere.nix" in error for error in errors), errors)

    def test_unknown_type_rejected(self):
        self.write(
            "docs/runbooks/example.md",
            VALID_PAGE.replace("type: Runbook", "type: Blog Post"),
        )
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("unknown document type" in error for error in errors), errors)

    def test_docs_page_without_frontmatter_rejected(self):
        self.write("docs/index.md", "# No frontmatter\n")
        errors = check_agent_docs.validate_tree(self.root)
        self.assertTrue(any("missing YAML frontmatter" in error for error in errors), errors)


class RepositoryFixture(unittest.TestCase):
    def test_repository_passes(self):
        root = os.environ.get("AGENT_DOCS_ROOT")
        if not root:
            self.skipTest("AGENT_DOCS_ROOT not set")
        errors = check_agent_docs.validate_tree(Path(root).resolve())
        self.assertEqual([], errors)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        os.environ["AGENT_DOCS_ROOT"] = sys.argv[1]
    unittest.main(argv=[sys.argv[0]], verbosity=2)
