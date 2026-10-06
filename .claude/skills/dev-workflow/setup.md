# Setup — worktree, deps, env

- **Worktree by ABSOLUTE path:** `git -C <repo> worktree add /…/NetPilot-Claude/worktrees/<repo>/<branch> -b <branch> origin/<default-branch>` (normally `main`; TopoViewer uses `development`).
  A relative path resolves against the `-C` cwd and lands the worktree inside the checkout (BE#446). Verify with `git worktree list`.
- **Fresh worktree = no deps, no env.** `pnpm install` / `uv sync --all-groups` (plain `uv sync` omits the `test` group →
  `Failed to spawn: pytest`); never copy `node_modules`/`.venv`. Copy the gitignored env files from the main checkout: backend
  `.env`/`.env.test`, frontend `.env.local`. Backend unit suite without `.env`: export the ENTIRE `env:` block of the workflow's
  unit-tests job — a missing `CORS_ORIGINS` reads as an auth regression (2026-09-09).
- **Next 16 `next dev` rewrites the tracked `CLAUDE.md`** (agentRules block) and bakes temp routes into `.next/dev/types` —
  `git checkout -- CLAUDE.md` and `rm -rf .next` before staging (FE PR#508, PR#253).
- **`vercel link` dirties the checkout it runs in** (`.gitignore`, `.env.local`) — link from a scratch dir; auth is global (FE PR#536).
- **Scratch files never go into a checkout;** run repo scripts from their own root. The scratchpad dir is SHARED by concurrent
  sessions of one project: name PR-body/replies files `<repo><pr>-…` and read line 1 back before `gh pr edit --body-file` —
  a generic `pr-body.md` was overwritten by a sibling session and pushed onto the wrong PR (mkt PR#205); scratch CLONES too —
  `mktemp -d <scratchpad>/<repo>-<pr>.XXXX` (the session's scratchpad path), never `rm -rf` a generic-named one (a `netpilot-skills/` clone was swapped mid-loop, skills PR#40).
- **Before `git worktree remove`, confirm no live background task is rooted there** (`lsof +D <wt>`) — a 40-min probe lost its
  run dir that way (2026-08-13). On a uv venv `lsof` also lists OTHER lanes' pythons (uv hardlinks packages from its cache, so
  the inodes are shared): read each PID's `/proc/<pid>/cwd` before calling the worktree busy (BE PR#934, clab PR#259).
  Long-running probes and watchers launch from the MAIN checkout.
- **A task that becomes a PR late:** create the worktree, COPY the durable files in, commit there, and say the worktree was a
  commit vehicle. `git pull --ff-only` aborts on locally modified/untracked copies of incoming files — byte-check, remove, pull.
- **A worktree that symlinks `node_modules`:** `git add -A` stages the symlink (the dir pattern in `.gitignore` misses it) and CI
  dies at `pnpm install` with `ENOTDIR`. `git show --stat HEAD` lists ONLY your files before every push (FE PR#265).
