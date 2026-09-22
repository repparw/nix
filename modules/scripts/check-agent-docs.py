#!/usr/bin/env python3
"""Validate the agent-facing Markdown corpus.

The repository routes agents through YAML frontmatter and repository-relative
links, so both must stay machine-readable. This check walks AGENTS.md, docs/,
and .agents/ and reports:

  * files that are not valid UTF-8, or that contain NUL bytes
  * frontmatter that does not parse, or is missing
  * required frontmatter fields by document type (and a `resource` that exists)
  * repository-relative Markdown links whose target does not exist

Usage:
    python3 check-agent-docs.py [REPOSITORY_ROOT]

Exit status is non-zero when any violation is reported.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

DOC_ROOTS = ("AGENTS.md", "docs", ".agents")
DOCS_PREFIX = "docs/"

BASE_FIELDS = ("type", "title", "description", "when", "tags")
RESOURCE_EXEMPT_TYPES = frozenset({"Agent Guide"})
KNOWN_TYPES = frozenset(
    {
        "Agent Guide",
        "Architecture Concept",
        "Documentation Index",
        "Host Profiles",
        "Research Note",
        "Runbook",
        "Service Architecture",
        "Troubleshooting",
        "Tweaks",
    }
)
SKILL_FIELDS = ("name", "description")

FRONTMATTER_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---[ \t]*\r?\n?", re.DOTALL)
FENCED_CODE_RE = re.compile(r"^(?:```|~~~).*?^(?:```|~~~)[ \t]*$", re.DOTALL | re.MULTILINE)
INLINE_CODE_RE = re.compile(r"`+[^`]*`+")
LINK_RE = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
IGNORED_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def iter_markdown(root: Path):
    for entry in DOC_ROOTS:
        path = root / entry
        if path.is_file():
            yield Path(entry)
        elif path.is_dir():
            for candidate in sorted(path.rglob("*.md")):
                yield candidate.relative_to(root)


def read_text(root: Path, rel: Path) -> tuple[str | None, list[str]]:
    """Return the decoded text and any text-integrity errors."""
    errors: list[str] = []
    data = (root / rel).read_bytes()
    if b"\x00" in data:
        errors.append(f"{rel}: contains NUL bytes")
    try:
        return data.decode("utf-8"), errors
    except UnicodeDecodeError as error:
        errors.append(f"{rel}: not valid UTF-8 ({error})")
        return None, errors


def split_frontmatter(text: str):
    match = FRONTMATTER_RE.match(text)
    if not match:
        return None, text
    return match.group(1), text[match.end() :]


def validate_frontmatter(rel: Path, frontmatter: str, errors: list[str]):
    try:
        data = yaml.safe_load(frontmatter)
    except yaml.YAMLError as error:
        errors.append(f"{rel}: frontmatter is not valid YAML ({error})")
        return None
    if not isinstance(data, dict):
        errors.append(f"{rel}: frontmatter must be a mapping")
        return None
    return data


def require_string(rel: Path, data: dict, field: str, errors: list[str]) -> bool:
    value = data.get(field)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{rel}: missing or empty frontmatter field `{field}`")
        return False
    return True


def validate_docs_frontmatter(rel: Path, data: dict, root: Path, errors: list[str]):
    doc_type = data.get("type")
    if not isinstance(doc_type, str) or not doc_type.strip():
        errors.append(f"{rel}: missing or empty frontmatter field `type`")
    elif doc_type not in KNOWN_TYPES:
        errors.append(f"{rel}: unknown document type `{doc_type}`")

    for field in ("type", "title", "description", "when"):
        require_string(rel, data, field, errors)

    tags = data.get("tags")
    if (
        not isinstance(tags, list)
        or not tags
        or not all(isinstance(tag, str) and tag.strip() for tag in tags)
    ):
        errors.append(f"{rel}: frontmatter `tags` must be a non-empty list of strings")

    if doc_type not in RESOURCE_EXEMPT_TYPES:
        if require_string(rel, data, "resource", errors):
            resource = data["resource"]
            if not (root / resource).exists():
                errors.append(f"{rel}: frontmatter `resource` does not exist: {resource}")


def validate_skill_frontmatter(rel: Path, data: dict, errors: list[str]):
    for field in SKILL_FIELDS:
        require_string(rel, data, field, errors)


def validate_links(rel: Path, text: str, root: Path, errors: list[str]):
    stripped = INLINE_CODE_RE.sub("", FENCED_CODE_RE.sub("", text))
    for match in LINK_RE.finditer(stripped):
        target = match.group(1).strip()
        if not target or target.startswith("#"):
            continue
        if IGNORED_SCHEME_RE.match(target):
            continue
        path = target.split("#", 1)[0].split("?", 1)[0]
        if not path:
            continue
        resolved = (root / rel.parent / path).resolve()
        if not resolved.exists():
            errors.append(f"{rel}: broken relative link -> {target}")


def validate_file(root: Path, rel: Path) -> list[str]:
    errors: list[str] = []
    text, text_errors = read_text(root, rel)
    errors.extend(text_errors)
    if text is None:
        return errors

    rel_posix = rel.as_posix()
    frontmatter, body = split_frontmatter(text)

    if frontmatter is None:
        if rel_posix.startswith(DOCS_PREFIX):
            errors.append(f"{rel}: documentation page is missing YAML frontmatter")
        return errors

    data = validate_frontmatter(rel, frontmatter, errors)
    if data is None:
        return errors

    if "type" in data:
        validate_docs_frontmatter(rel, data, root, errors)
    elif "name" in data:
        validate_skill_frontmatter(rel, data, errors)
    else:
        errors.append(f"{rel}: frontmatter has neither `type` nor `name`")

    validate_links(rel, body, root, errors)
    return errors


def validate_tree(root: Path) -> list[str]:
    errors: list[str] = []
    for rel in iter_markdown(root):
        errors.extend(validate_file(root, rel))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", help="repository root")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    errors = validate_tree(root)
    if errors:
        for error in errors:
            print(f"check-agent-docs: {error}", file=sys.stderr)
        print(f"check-agent-docs: {len(errors)} violation(s)", file=sys.stderr)
        return 1

    print("check-agent-docs: frontmatter and links valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
