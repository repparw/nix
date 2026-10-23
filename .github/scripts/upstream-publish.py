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


def arm_automerge(repo, number):
    # GitHub merges the candidate exactly when the required checks pass and
    # the branch is current with main (strict up-to-date protection). A
    # repeat request on an already-armed candidate is not an error.
    try:
        run("gh", "pr", "merge", str(number), "--repo", repo, "--squash", "--auto")
    except subprocess.CalledProcessError as error:
        output = (error.stdout or "") + (error.stderr or "")
        if "already" not in output.lower():
            raise ValueError(f"auto-merge request failed: {output.strip()[:200]}") from None


def expected_tree(candidate, base, patch):
    # The exact tree the recipe produces when applied to `base`.
    environment = {**os.environ, "GIT_INDEX_FILE": str(candidate.parent / f"expected-index-{base[:8]}")}
    run("git", "read-tree", base, cwd=candidate, env=environment)
    run("git", "apply", "--cached", str(patch), cwd=candidate, env=environment)
    return run("git", "write-tree", cwd=candidate, env=environment)


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
                # The candidate must equal the recipe applied to current main.
                # An automation-authored tip that predates a main advance is
                # refreshed onto main and revalidated; anything else needs
                # review, and is never overwritten.
                run("git", "fetch", "--quiet", "origin", "refs/heads/main", cwd=candidate)
                main_sha = run("git", "rev-parse", "FETCH_HEAD", cwd=candidate)
                branch_tree = run("git", "rev-parse", "HEAD^{tree}", cwd=candidate)
                main_expected = expected_tree(candidate, main_sha, patch)
                if branch_tree != main_expected:
                    tip_expected = expected_tree(candidate, "HEAD^", patch)
                    single = run("git", "rev-list", "--count", "HEAD^..HEAD", cwd=candidate)
                    if branch_tree != tip_expected or single != "1":
                        raise ValueError("candidate differs from the exact cleanup recipe")
                    run("git", "checkout", "--quiet", "--detach", main_sha, cwd=candidate)
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
                    refreshed = run("git", "rev-parse", "HEAD", cwd=candidate)
                    run("git", "push", f"--force-with-lease=refs/heads/{branch}:{sha}",
                        "origin", f"HEAD:refs/heads/{branch}", cwd=candidate)
                    sha = refreshed
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
                                "the package-specific checks. Auto-merge fires when the required "
                                "checks pass and main has not moved; a stale or changed candidate "
                                "requires review.\n")
                url = run("gh", "pr", "create", "--repo", repo, "--base", "main",
                          "--head", branch, "--title", f"fix(upstream): retire {name} workaround",
                          "--body-file", str(body))
                number = int(url.rsplit("/", 1)[1])
            dispatch_missing(repo, branch, sha, number, name)
            arm_automerge(repo, number)
            return {"pr": number, "sha": sha, "status": "automerge-armed"}
        finally:
            run("git", "worktree", "remove", "--force", str(candidate))


NOTIFY_STATE_REF = "automation/upstream-notify-state"


def discord_post(content):
    """Post to the fleet channel through the approved bot identity.

    Every other fleet watcher delivers this way — token in the hermes-env
    sops secret, channel from modules/service-definitions.nix — instead of
    per-aspect webhooks. The token stays off argv: curl reads it from a
    private config file. A missing identity fails the run: a ready notice
    must not stay silent.
    """
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    channel = os.environ.get("DISCORD_CHANNEL_ID", "").strip()
    if not token or not channel:
        raise ValueError("DISCORD_BOT_TOKEN/DISCORD_CHANNEL_ID are not configured")
    with tempfile.TemporaryDirectory(prefix="upstream-notify-") as directory:
        payload = Path(directory) / "payload.json"
        payload.write_text(json.dumps({"content": content}))
        config = Path(directory) / "curl-config"
        config.write_text(
            f'url = "https://discord.com/api/v10/channels/{channel}/messages"\n'
            f'header = "Authorization: Bot {token}"\n'
            'header = "Content-Type: application/json"\n'
            f'data-binary = "@{payload}"\n')
        subprocess.run(["curl", "--fail", "--silent", "--show-error", "--max-time", "30",
                        "--config", str(config)],
                       check=True, capture_output=True, text=True, timeout=120)


def notify_state():
    listing = run("git", "ls-remote", "origin", f"refs/heads/{NOTIFY_STATE_REF}")
    if not listing:
        return None, {}
    run("git", "fetch", "--quiet", "--force", "origin",
        f"refs/heads/{NOTIFY_STATE_REF}:refs/heads/{NOTIFY_STATE_REF}")
    return listing.split()[0], json.loads(
        run("git", "show", f"refs/heads/{NOTIFY_STATE_REF}:state.json"))


def record_notify_state(previous, state):
    # Single-commit state ref, mirroring the atomic-cleanup provenance ref.
    # A concurrent writer that wins the lease also delivered its notice and
    # the next run converges, so a lost state update is tolerated.
    with tempfile.TemporaryDirectory(prefix="upstream-notify-state-") as directory:
        state_file = Path(directory) / "state.json"
        state_file.write_text(json.dumps(state, sort_keys=True, indent=2) + "\n")
        environment = {**os.environ, "GIT_INDEX_FILE": str(Path(directory) / "index")}
        blob = run("git", "hash-object", "-w", str(state_file))
        run("git", "read-tree", "--empty", env=environment)
        run("git", "update-index", "--add", "--cacheinfo", f"100644,{blob},state.json",
            env=environment)
        tree = run("git", "write-tree", env=environment)
        identity = {
            "GIT_AUTHOR_NAME": "github-actions[bot]",
            "GIT_AUTHOR_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
            "GIT_COMMITTER_NAME": "github-actions[bot]",
            "GIT_COMMITTER_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
        }
        commit = run("git", "commit-tree", tree, "-m", "upstream-watch: notify state",
                     env={**environment, **identity})
        expected = previous or ""
        run("git", "push", f"--force-with-lease=refs/heads/{NOTIFY_STATE_REF}:{expected}",
            "origin", f"{commit}:refs/heads/{NOTIFY_STATE_REF}")


def notify(name, spec, repo, status):
    """Deliver a ready notice to Discord once per status change.

    The upstream-watch run summary carries the status every run; the ping
    exists for time-sensitive candidates. Delivery state lives on the
    automation/upstream-notify-state ref instead of per-issue comment
    markers, so no tracked issue is involved. A missing or failing Discord
    identity fails the run: a ready notice must not stay silent.
    """
    previous, state = notify_state()
    if state.get(name) == status:
        return {"status": "already-notified"}
    if name == "fsr4-rdna2" and status.startswith("upstream-review-required:"):
        tag = status.split(":", 1)[1]
        if not re.fullmatch(r"GE-Proton[0-9]+-[0-9]+", tag):
            raise ValueError("invalid GE candidate release")
        content = (f"GE-Proton has relevant FSR4/RDNA2 release changes: "
                   f"https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/{tag}\n\n"
                   "Review the runner, AMD model and RADV requirements and test on Alpha's RX 6700 XT. "
                   "This is a candidate, not confirmed support or pinned readiness. "
                   "Record the tested upstream support commit in watchers.json to arm exact-ancestry "
                   "tracking through the channel and root pin. No global FSR setting was changed.")
    else:
        content = (f"CI detected `{status}` for `{name}` on main: the checked-out pin "
                   "contains the upstream fix. Deployment and runtime completion remain "
                   "subject to their own checks. Details: "
                   f"https://github.com/{repo}/actions/workflows/upstream-watch.yml")
    discord_post(content)
    state[name] = status
    try:
        record_notify_state(previous, state)
    except subprocess.CalledProcessError:
        pass
    return {"status": "notified"}


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
            elif (name == "fsr4-rdna2" and spec["mode"] == "notify-only"
                  and status.startswith("upstream-review-required:")):
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

