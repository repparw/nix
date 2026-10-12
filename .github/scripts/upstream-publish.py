#!/usr/bin/env python3
"""Publish independent cleanup candidates from the checked-out main revision."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True, timeout=120, env=env).stdout.strip()


def gh_json(*args):
    return json.loads(run("gh", *args))


def patch_paths(patch):
    paths = re.findall(r"^diff --git a/(\S+) b/(\S+)$", patch.read_text(), re.M)
    if not paths or any(a != b or not a.startswith("modules/") or ".." in Path(a).parts
                        for a, b in paths):
        raise ValueError("cleanup must contain only module changes without renames")
    return {a for a, _ in paths}


def dispatch_missing(repo, branch, sha, number, watcher):
    # Recover a crash between publishing a PR and dispatching its checks.
    # Existing runs, including failures, belong to reviewers and are retained.
    for workflow in ("pr-title.yml", "ci.yml"):
        runs = gh_json("run", "list", "--repo", repo, "--workflow", workflow,
                       "--commit", sha, "--json", "headSha", "--limit", "100")
        if runs:
            continue
        arguments = ["gh", "workflow", "run", workflow, "--repo", repo,
                     "--ref", branch, "-f", f"expected_sha={sha}"]
        arguments += (["-f", f"pull_request_number={number}"] if workflow == "pr-title.yml"
                      else ["-f", f"upstream_watcher={watcher}"])
        run(*arguments)


def publish(name, spec, repo):
    if not re.fullmatch(r"[a-z0-9-]+", name):
        raise ValueError("invalid watcher id")
    patch = ROOT / ".github/upstream/cleanup" / spec["cleanup"]
    if patch.parent != ROOT / ".github/upstream/cleanup" or patch.suffix != ".patch":
        raise ValueError("invalid cleanup path")
    paths = patch_paths(patch)
    branch = f"automation/upstream-{name}"
    prs = gh_json("pr", "list", "--repo", repo, "--head", branch, "--base", "main",
                  "--state", "open", "--json", "number,headRefOid")
    remote = run("git", "ls-remote", "--heads", "origin", f"refs/heads/{branch}")
    sha = remote.split()[0] if remote else None
    if prs and (len(prs) != 1 or not sha or prs[0]["headRefOid"] != sha):
        raise ValueError("open PR and remote branch disagree")
    if not prs:
        # Check before branch creation, including a closed PR whose branch was
        # deleted. Rejected candidates must not recreate an orphan branch.
        previous = gh_json("pr", "list", "--repo", repo, "--head", branch,
                           "--state", "closed", "--json", "number")
        if previous:
            raise ValueError("branch belongs to a closed PR; needs review")
    with tempfile.TemporaryDirectory(prefix="upstream-candidate-") as directory:
        candidate = Path(directory) / "checkout"
        if sha:
            run("git", "fetch", "--quiet", "origin", f"refs/heads/{branch}")
            run("git", "worktree", "add", "--detach", str(candidate), sha)
        else:
            run("git", "worktree", "add", "--detach", str(candidate), "HEAD")
        try:
            if sha:
                # Reconstruct the expected tree. Reverse-checking a deletion
                # patch alone would accept any text inserted by its reverse.
                environment = {**os.environ, "GIT_INDEX_FILE": str(Path(directory) / "expected-index")}
                run("git", "read-tree", "HEAD^", cwd=candidate, env=environment)
                run("git", "apply", "--cached", "--check", str(patch), cwd=candidate, env=environment)
                run("git", "apply", "--cached", str(patch), cwd=candidate, env=environment)
                expected = run("git", "write-tree", cwd=candidate, env=environment)
                if expected != run("git", "rev-parse", "HEAD^{tree}", cwd=candidate):
                    raise ValueError("candidate differs from the exact cleanup recipe")
            else:
                run("git", "apply", "--check", str(patch), cwd=candidate)
                run("git", "apply", str(patch), cwd=candidate)
                changed = set(run("git", "diff", "--name-only", cwd=candidate).splitlines())
                if changed != paths:
                    raise ValueError("cleanup changed unexpected paths")
                run("git", "add", "--", *sorted(paths), cwd=candidate)
                run("git", "-c", "user.name=github-actions[bot]", "-c",
                    "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                    "-c", "core.hooksPath=/dev/null", "commit", "-m",
                    f"fix(upstream): retire {name} workaround", cwd=candidate)
                sha = run("git", "rev-parse", "HEAD", cwd=candidate)
                # Require the branch to be absent, including races with another writer.
                run("git", "push", f"--force-with-lease=refs/heads/{branch}:",
                    "origin", f"HEAD:refs/heads/{branch}", cwd=candidate)
            if prs:
                number = prs[0]["number"]
            else:
                # This also recovers a published branch whose PR creation failed.
                body = Path(directory) / "body.md"
                body.write_text(f"Retires the {name} workaround after the upstream fix reached "
                                "the flake's checked-out pin.\n\n"
                                f"Cleanup recipe: `.github/upstream/cleanup/{patch.name}`.\n"
                                f"Candidate: `{sha}`.\n\n"
                                "CI validates the exact revision, evaluates the fleet, and runs "
                                "the package-specific checks. Review is required before merging.\n")
                url = run("gh", "pr", "create", "--repo", repo, "--base", "main",
                          "--head", branch, "--title", f"fix(upstream): retire {name} workaround",
                          "--body-file", str(body))
                number = int(url.rsplit("/", 1)[1])
            dispatch_missing(repo, branch, sha, number, name)
            return {"pr": number, "sha": sha, "status": "waiting-ci-or-review"}
        finally:
            run("git", "worktree", "remove", "--force", str(candidate))


def notify(name, spec, repo, status):
    issue = spec.get("issue")
    if not isinstance(issue, int):
        raise ValueError("notification requires a tracked issue")
    marker = f"<!-- upstream-watch:{name}:{status} -->"
    comments = gh_json("api", "--paginate", "--slurp",
                       f"repos/{repo}/issues/{issue}/comments?per_page=100")
    if any(marker in comment.get("body", "") for page in comments for comment in page):
        return {"issue": issue, "status": "already-notified"}
    with tempfile.TemporaryDirectory(prefix="upstream-notify-") as directory:
        body = Path(directory) / "body.md"
        body.write_text(f"{marker}\nCI detected `{status}` for `{name}` on main. "
                        "The checked-out pin contains the upstream fix. "
                        "Deployment and runtime completion remain subject to their own checks.\n")
        run("gh", "issue", "comment", str(issue), "--repo", repo, "--body-file", str(body))
    return {"issue": issue, "status": "notified"}


def sweep(registry, readiness, repo):
    results = {}
    failed = False
    for name, spec in registry.items():
        status = readiness.get(name, "unavailable (missing detector)")
        try:
            if spec["mode"] not in ("atomic", "post-lock", "notify-only", "host-owned", "completed"):
                raise ValueError("unsupported watcher mode")
            if status == "PINNED-READY" and spec["mode"] == "post-lock":
                results[name] = publish(name, spec, repo)
            elif status == "PINNED-READY" and spec["mode"] in ("notify-only", "host-owned"):
                results[name] = notify(name, spec, repo, status)
            else:
                results[name] = {"status": status}
                if status.startswith("unavailable"):
                    failed = True
        except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError) as error:
            # Avoid emitting transport output or credentials from subprocesses.
            results[name] = {"status": f"needs-attention ({type(error).__name__})"}
            failed = True
    return results, failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--readiness", type=Path, required=True)
    args = parser.parse_args()
    registry = json.loads((ROOT / ".github/upstream/watchers.json").read_text())
    readiness = json.loads(args.readiness.read_text())
    repo = os.environ["GH_REPO"]
    results, failed = sweep(registry, readiness, repo)
    print(json.dumps(results, indent=2, sort_keys=True))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as output:
            output.write("\n### Independent upstream watchers\n\n```json\n" +
                         json.dumps(results, indent=2, sort_keys=True) + "\n```\n")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
