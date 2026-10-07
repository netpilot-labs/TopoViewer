#!/usr/bin/env python3
"""Reply to + resolve Codex review threads on a PR, keyed by inline-comment database id.

usage: pr-threads.py <owner/repo> <pr> <sha> <replies.json>
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
    replies = json.load(open(args[3])) if len(args) > 3 else {}
    owner, name = repo.split("/", 1)

    q = """query($owner:String!,$name:String!,$pr:Int!){ repository(owner:$owner,name:$name){
      pullRequest(number:$pr){ reviewThreads(last:100){ nodes{ id isResolved
        comments(first:1){ nodes{ databaseId path line originalLine } } } } } } }"""
    nodes = gql(q, {"owner": owner, "name": name, "pr": pr})["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    by_comment = {str(t["comments"]["nodes"][0]["databaseId"]): t for t in nodes if t["comments"]["nodes"]}

    if dry:
        for cid, t in by_comment.items():
            c = t["comments"]["nodes"][0]
            print(f"{'resolved' if t['isResolved'] else 'OPEN    '} thread={t['id']} comment={cid} {c['path']}:{c['line'] or c['originalLine']}")
        return

    for cid, spec in replies.items():
        t = by_comment.get(cid)
        if t is None:
            raise SystemExit(f"no review thread starts with comment {cid} (run --dry-run to list)")
        if isinstance(spec, str):  # a bare string = {"text": ..., "resolve": true} (mkt PR#243, 2026-10-04)
            spec = {"text": spec, "resolve": True}
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
