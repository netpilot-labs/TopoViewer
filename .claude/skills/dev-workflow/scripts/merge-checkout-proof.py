#!/usr/bin/env python3
"""Prove stale-base CI checked out a merge of the current default tip and PR head.

Workflow run/check-suite head_sha identifies the PR branch, not its tested merge.
Only the successful checkout action's recorded full commit SHA plus immutable Git
parents supplies that proof. Missing/expired/unsupported logs require a rebase.
"""
import datetime
import json
import re
import subprocess
import sys


def api(route, *, pages=False, logs=False):
    args = ["gh", "api", route]
    if pages:
        args += ["--paginate", "--slurp"]
    if logs:
        args += ["--allow-escape-sequences"]
    result = subprocess.run(args, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise ValueError("GitHub evidence unavailable")
    return result.stdout if logs else json.loads(result.stdout)


def epoch(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def checkout_sha(log, steps, pr):
    windows = [s for s in steps if re.fullmatch(r"Run actions/checkout@v[2-6]", s.get("name", ""))
               and s.get("status") == "completed" and s.get("conclusion") == "success"]
    if len(windows) != 1:
        raise ValueError("one successful standard checkout action required per job")
    step = windows[0]
    start, end = epoch(step["started_at"]), epoch(step["completed_at"]) + 1
    lines = []
    for line in log.splitlines():
        stamp, separator, text = line.partition(" ")
        if separator:
            try:
                if start <= epoch(stamp) < end:
                    lines.append(text)
            except ValueError:
                pass
    checkouts = [x for x in lines if re.fullmatch(
        r"\[command\].*/git checkout --progress --force refs/remotes/pull/" + str(pr) + r"/merge", x)]
    hashes = []
    for i, text in enumerate(lines[:-1]):
        if re.fullmatch(r"\[command\].*/git log -1 --format=%H", text):
            if re.fullmatch(r"[0-9a-f]{40}", lines[i + 1]):
                hashes.append(lines[i + 1])
    if len(checkouts) != 1 or len(hashes) != 1:
        raise ValueError("unambiguous default PR-merge checkout SHA missing")
    return hashes[0]


def prove(repo, pr, head, tip, runs):
    parents = {}
    for run in runs:
        run_id, attempt = run.get("id"), run.get("run_attempt")
        if not isinstance(run_id, int) or not isinstance(attempt, int) or attempt < 1:
            raise ValueError("run attempt identity missing")
        pages = api(f"repos/{repo}/actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100", pages=True)
        jobs = [job for page in pages for job in page["jobs"]]
        successful = [job for job in jobs if job.get("status") == "completed" and job.get("conclusion") == "success"]
        if not successful:
            raise ValueError("no successful job checkout evidence")
        for job in successful:
            sha = checkout_sha(api(f"repos/{repo}/actions/jobs/{job['id']}/logs", logs=True), job["steps"], pr)
            if sha not in parents:
                commit = api(f"repos/{repo}/commits/{sha}")
                if commit.get("sha") != sha:
                    raise ValueError("checkout commit identity differs")
                parents[sha] = [p["sha"] for p in commit["parents"]]
            if parents[sha] != [tip, head]:
                raise ValueError("CI checkout did not merge current default tip with current PR head")
    if not runs:
        raise ValueError("no workflow evidence")


def main():
    try:
        repo, pr, head, tip, filename = sys.argv[1:]
        with open(filename) as source:
            prove(repo, int(pr), head, tip, json.load(source))
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print("merge checkout proof: unavailable — " + str(error), file=sys.stderr)
        return 1
    print("merge checkout proof: every successful job tested the current default tip and PR head")
    return 0


if __name__ == "__main__":
    sys.exit(main())
