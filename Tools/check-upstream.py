#!/usr/bin/env python3
"""Read-only upstream assessment. Fetches refs, never checks out or merges files."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request


def git(repo, *args, allowed=(0,)):
    result = subprocess.run(["git", "-C", str(repo), *args], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    if result.returncode not in allowed:
        raise RuntimeError(f"git {args[0]} failed: {result.stderr.strip()}")
    return result


def assess(repo, fork_ref, upstream_ref, state, today):
    fork = git(repo, "rev-parse", "--verify", f"{fork_ref}^{{commit}}").stdout.strip()
    upstream = git(repo, "rev-parse", "--verify", f"{upstream_ref}^{{commit}}").stdout.strip()
    base = git(repo, "merge-base", fork, upstream).stdout.strip()
    recorded = state["upstream_commit"]
    if git(repo, "merge-base", "--is-ancestor", recorded, fork, allowed=(0, 1)).returncode:
        raise RuntimeError("Recorded upstream baseline is not an ancestor of the fork ref")
    if git(repo, "merge-base", "--is-ancestor", recorded, upstream, allowed=(0, 1)).returncode:
        raise RuntimeError("Upstream history diverged from the recorded baseline; review manually")
    pending = int(git(repo, "rev-list", "--count", f"{fork}..{upstream}").stdout)
    fork_files = set(git(repo, "diff", "--name-only", base, fork).stdout.splitlines())
    upstream_files = set(git(repo, "diff", "--name-only", base, upstream).stdout.splitlines())
    preview = git(repo, "merge-tree", "--write-tree", "--name-only", fork, upstream, allowed=(0, 1))
    # With --name-only the first section is a tree OID, then one path per
    # conflicted file. Messages after the blank line are not file names.
    first = preview.stdout.split("\n\n", 1)[0].splitlines()
    conflicts = sorted(set(first[1:])) if preview.returncode else []
    days = (today - dt.date.fromisoformat(state["integrated_on"])).days
    reasons = []
    if pending >= 50:
        reasons.append("At least 50 pending commits")
    if pending and days >= 14:
        reasons.append("Pending changes and at least 14 days since integration")
    return {
        "fork_commit": fork, "upstream_commit": upstream, "merge_base": base,
        "recorded_upstream_commit": recorded, "days_since_integration": days,
        "pending_commits": pending, "upstream_changed_files": len(upstream_files),
        "overlapping_files": sorted(fork_files & upstream_files),
        "conflict_files": conflicts, "priority_reasons": reasons,
        "pending_log": git(repo, "log", "--format=%h %cs %s", f"{fork}..{upstream}").stdout.splitlines(),
        "dirty_worktree": bool(git(repo, "status", "--porcelain").stdout),
        "release_check": "not_requested", "latest_release": None,
    }


def latest_release():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "vorssaint-mytool-upstream-check"}
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        "https://api.github.com/repos/vorssaint/vorssaint-utils/releases/latest", headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        data = json.load(response)
    return {key: data[key] for key in ("tag_name", "published_at", "html_url")}


def markdown(report):
    release = report["latest_release"]
    lines = ["# Upstream assessment", "",
             f"- Fork: `{report['fork_commit']}`",
             f"- Upstream: `{report['upstream_commit']}`",
             f"- Pending commits: **{report['pending_commits']}**",
             f"- Days since integration: {report['days_since_integration']}",
             f"- Overlapping files: {len(report['overlapping_files'])}",
             f"- Merge conflicts: {len(report['conflict_files'])}",
             f"- Latest stable release: {release['tag_name'] if release else report['release_check']}",
             f"- Priority: {'; '.join(report['priority_reasons']) or 'normal'}", "",
             "Assessment uses committed refs; dirty working files are excluded.",
             "No checkout, merge, push, install or release was performed."]
    for title, key in (("Conflicts", "conflict_files"), ("Overlap", "overlapping_files"), ("Pending commits", "pending_log")):
        lines += ["", f"## {title}", ""] + [f"- {entry}" for entry in report[key]]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--fork-ref", default="HEAD")
    parser.add_argument("--upstream-ref", default="upstream/main")
    parser.add_argument("--state", type=Path)
    parser.add_argument("--no-fetch", action="store_true")
    parser.add_argument("--no-release-check", action="store_true")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    args = parser.parse_args()
    try:
        if not args.no_fetch:
            git(args.repo, "fetch", "--no-tags", "upstream")
        state_path = args.state or args.repo / "docs/upstream-state.json"
        state = json.loads(state_path.read_text())
        today = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).date()
        report = assess(args.repo, args.fork_ref, args.upstream_ref, state, today)
        if not args.no_release_check:
            report["latest_release"] = latest_release()
            report["release_check"] = "ok"
            if report["latest_release"]["tag_name"] != state["official_release"]:
                report["priority_reasons"].append("Official stable release differs from last reviewed release")
        print(json.dumps(report, ensure_ascii=False, indent=2) if args.format == "json" else markdown(report), end="\n")
        return 0
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"Upstream assessment failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
