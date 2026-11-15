# AGENTS.md

How the repo works, its layout and conventions: [docs/development.md](docs/development.md). On top of that:

- This repo configures the Mac it runs on. Never run `install.sh`, `mise bootstrap`, `mise run bootstrap` or
  `mise dot apply` here: test on a VM (`mise run test:func personal`).
- Before `mise exec` against `config/mise`, set `MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false`, or
  mise installs every tool of the recipe on this Mac.
- Templates in `config/secrets` hold `op://` references only. Never write a secret's value or print a token.
- `~/.claude` belongs to Claude Code: only the status line script and the `statusLine` key come from here.
- Verify every change with `mise run check`; one to `install.sh`, `scripts/` or `config/mise` also with
  `mise run test:func personal`. Delete the VMs that `--keep` leaves.
- Commit and push only when asked.
