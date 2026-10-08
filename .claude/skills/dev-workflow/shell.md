# Shell — rules for any chain you write by hand (prefer the scripts)

The harness runs every command through a zsh `eval` on macOS; all of these are verified there.
- **`set -e` protects nothing here** — a failing plain command and a failing pipe both continue (BE PR#860, PR#800). Gate every
  step on its own status: `cmd > out.txt 2>&1; RC=$?; [ $RC -eq 0 ] || exit 1`. Test red positively — `if grep -qE
  "failed|error" out.txt; then exit 1; fi` — never `grep " passed"`, never `! grep` (exempt from errexit).
- **`cmd | tail -1 && next` runs `next` on a red `cmd`** — the status is tail's (BE#375, PR#673). Capture, check `$?`, then display.
- **An `&&` chain ends at a newline and at a heredoc terminator**; later lines run unconditionally (BE PR#698, lab PR#38).
  Write message/body files as the FIRST statements, then ONE unbroken gated chain.
- **Two tool calls in one message share one shell** — their `cd`s race, and a parse error aborts a leading `cd` while later
  calls keep the old cwd (BE#349, mkt PR#190). Absolute paths and `git -C <abs>` always; cwd-bound builds as separate
  sequential calls; start edit batches with `pwd | grep -q <branch> || exit 99`.
- **Backticks in a double-quoted string or an unquoted heredoc are command substitution** — gh bodies, GraphQL `-f` strings and
  python edit scripts lose their code spans silently. Quoted heredoc (`<<'EOF'`) to a file, then `--body-file` / `-F var=@file`.
- **zsh:** quote every URL with `?` and every glob-shaped flag value (`no matches found` reads as "no runs yet" in a loop);
  `$var[` is subscript syntax; never `read` into `path` or assign `status`; an unquoted `$F` does not word-split — `while read -r`; `read -a` is bash-only: split with `IFS=, read -rA arr` or `${(s:,:)var}`, and zsh arrays index from 1, so loop with `for x in "${arr[@]}"` rather than `${arr[0]}` (mkt #260–#275, 2026-10-07);
  `$pipestatus`, not `$PIPESTATUS`; `mktemp -d` with a glob in its template dies — resolve the path into a variable first;
  a word starting with `=` is `=cmd` expansion — `echo =====` dies (`===== not found`) and skips the rest of the chain.
- **macOS:** no `timeout` — use the CLI's own bound, `perl -e 'alarm shift; exec @ARGV or exit 127' <sec> <cmd…>` (exit 142 at
  the bound; without the `or exit 127` a missing command exits 0; a command that ignores SIGALRM is NOT bounded —
  `redproof.sh` uses a watchdog; clab PR#265, BE PR#953) or `gtimeout`; bash 3.2 (no `declare -A`); BSD `find -newermt` ignores relative times;
  BSD grep has no `\|` (use `grep -E`); a macOS run is not CI-parity for shell (`tar | head` SIGPIPEs GNU tar).
- **Scripted edits:** `assert s.count(old) == 1` against a FRESH read (ruff/format invalidates anchors); `str.replace` is
  replace-all by default; `python3 … || exit 1` — a heredoc-python assert does not stop the chain. Verify claims by RUNNING the
  artifact, never by grepping text you just wrote. Write/Edit decode `\uXXXX` in content — escape TEXT needs a quoted-heredoc
  python writer (BE PR#767). `Path.read_text`/`write_text` rewrite a CRLF file as LF: a 10-line edit became a 1,250-line
  diff — check `file <path>` and edit a CRLF file as bytes (mkt PR#232).
- **`pgrep -f` guards match their own wrapper shell** — anchor on the interpreter path from a script FILE:
  `pgrep -f '^/.*/\.venv/bin/python /.*/\.venv/bin/pytest'` (boards 26/27). A background waiter `until [ "$(pgrep -f
  <name> | wc -l)" = 0 ]` matches its own command line and never ends — wait on a PID or a marker file (board 31 sweep).
- **`bash -n` does not parse a script embedded in a heredoc** — an apostrophe inside a single-quoted awk program broke the
  embedded file while the outer check stayed green; give every embedded script its own `bash -n` (clab PR#266).
- **`git diff --quiet <ref> -- <path>` reads an UNTRACKED file as deleted, whatever its bytes** (exit 1 on an identical file:
  the working-tree side comes through the index). Byte-check a generated or not-yet-added file against the merged version by
  blob id — no temp file, no pipe, `--no-filters` so a CRLF/clean filter cannot hash converted bytes:
  `h=$(git hash-object --no-filters <path>) || exit 1; [ "$(git rev-parse -q --verify <ref>:<path>)" = "$h" ] || exit 1` (a
  missing ref path yields an empty string, never a match; a bare `git show … | cmp -s - <path>` reports a MATCH when the ref
  is unreadable and the local file empty) (the ten consumer-snapshot lanes, 2026-10-07; Codex R1–R6).
- **`cp` onto an EXISTING file keeps the destination's mode** (macOS, verified: 755 onto 644 stays 644; onto an absent path the
  source mode copies): a sync-written executable arrives non-executable in the worktree — `cp -p`, then `git diff --summary |
  grep mode` before the push (clab PR#278, 2026-10-07).
- **Never hand-type a 40-char oid** — capture it (`git rev-parse HEAD`, `--json headRefOid`) (FE#309, BE#410).
- **`gh issue view <n> --comments` in this non-TTY harness prints the comments WITHOUT the issue body, and nothing at all
  (exit 0) for an issue that has no comment** — it reads like a failed fetch or an empty issue. Read an issue with
  `gh issue view <n> --json title,body,comments --jq …` (skills#56, BE#963).
- **Never `2>/dev/null` a status source;** `jq '.[0].id'` on `[]` prints `null`, which passes an emptiness guard — `// empty`.
