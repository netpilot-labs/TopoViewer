#!/usr/bin/env python3
"""Reply to + resolve Codex review threads on a PR, keyed by inline-comment database id.

usage: pr-threads.py <owner/repo> <pr> <sha> <replies.json>   # <sha> = the full 40-char head oid (head7 is refused)
       pr-threads.py <owner/repo> <pr> --dry-run      # 2 args only — do NOT pass a
                                                      # replies path (/dev/null is not
                                                      # valid JSON and raises)
  replies.json: {"<comment_db_id>": {"text": "Fixed in <sha>: ...", "resolve": true}, ...}
  "<sha>" inside a text is replaced by the sha argument. --dry-run prints every thread
  (id, first comment id, path:line, resolved?) and posts nothing.

Provenance: hand-rolled three times on FE PR#508 (2026-09-13) — the GraphQL thread-id
lookup is the part every lane got wrong once. Run only AFTER `git diff --stat HEAD~1`
lists every file the replies claim (dev-workflow review.md, the loop step 3).
"""
import json
import re
import subprocess
import sys


def gql(query, variables):
    out = subprocess.run(
        ["gh", "api", "graphql", "--input", "-"],
        input=json.dumps({"query": query, "variables": variables}),
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise SystemExit(f"graphql failed: {out.stderr.strip()}")
    data = json.loads(out.stdout)
    if data.get("errors"):
        raise SystemExit(f"graphql errors: {data['errors']}")
    return data


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if (dry and len(args) < 2) or (not dry and len(args) != 4):
        raise SystemExit(__doc__)
    repo, pr = args[0], int(args[1])
    sha = args[2] if len(args) > 2 else ""
    if not dry and not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SystemExit("reply SHA must be the full hexadecimal current PR head; no mutations were posted")
    replies = {}
    if len(args) > 3:
        with open(args[3]) as reply_file:
            replies = json.load(reply_file)
    owner, name = repo.split("/", 1)

    q = """query($owner:String!,$name:String!,$pr:Int!){ repository(owner:$owner,name:$name){
      pullRequest(number:$pr){ headRefOid reviewThreads(last:100){ totalCount nodes{ id isResolved
        comments(first:1){ nodes{ databaseId path line originalLine } } } } } } }"""
    snapshot = gql(q, {"owner": owner, "name": name, "pr": pr})["data"]["repository"]["pullRequest"]
    if not dry and snapshot.get("headRefOid") != sha:
        raise SystemExit("reply SHA does not match the current PR head; no replies or resolutions were posted")
    threads = snapshot["reviewThreads"]
    nodes = threads["nodes"]
    if threads.get("totalCount") != len(nodes):
        raise SystemExit("review thread window is incomplete; no replies or resolutions were posted")
    by_comment = {str(t["comments"]["nodes"][0]["databaseId"]): t for t in nodes if t["comments"]["nodes"]}

    if dry:
        for cid, t in by_comment.items():
            c = t["comments"]["nodes"][0]
            print(f"{'resolved' if t['isResolved'] else 'OPEN    '} thread={t['id']} comment={cid} {c['path']}:{c['line'] or c['originalLine']}")
        return

    if not isinstance(replies, dict):
        raise SystemExit("replies must be an object keyed by comment id")
    plan = []
    for cid, spec in replies.items():
        t = by_comment.get(cid)
        if t is None:
            raise SystemExit(f"no review thread starts with comment {cid} (run --dry-run to list)")
        if isinstance(spec, str):
            spec = {"text": spec, "resolve": True}
        if (not isinstance(spec, dict) or not isinstance(spec.get("text"), str)
                or not spec["text"].strip() or not isinstance(spec.get("resolve", False), bool)):
            raise SystemExit(f"invalid reply payload for {cid}: nonempty text and boolean resolve required")
        plan.append((cid, t, spec))

    for cid, t, spec in plan:
        text = spec["text"].replace("<sha>", sha)
        r = subprocess.run(
            ["gh", "api", f"repos/{repo}/pulls/{pr}/comments/{cid}/replies", "-X", "POST", "--input", "-"],
            input=json.dumps({"body": text}),
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            raise SystemExit(f"reply failed for {cid}: {r.stderr.strip()}")
        if spec.get("resolve"):
            gql("mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }", {"id": t["id"]})
        print("replied" + (" + resolved" if spec.get("resolve") else ""), cid)


if __name__ == "__main__":
    main(sys.argv[1:])
