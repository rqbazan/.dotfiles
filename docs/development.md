# Development

How the repo works, how to change it, and how to test a change before it reaches a Mac. For the manual
steps on a Mac, see the [runbook](runbook.md).

## How it works

`install.sh` installs Homebrew and mise, stores the profile and the 1Password token, then runs
`mise bootstrap`. From then on the repo lives at `~/.dotfiles`, and `~/.config/mise` is a symlink to
`~/.dotfiles/config/mise`: the repo's config is the Mac's global mise config.

| What | Declared in | Applied by |
| --- | --- | --- |
| Apps, fonts and a few CLIs (Homebrew), App Store apps (mas) | `[bootstrap.packages]` | `mise bootstrap` |
| Runtimes and CLIs, at pinned versions | `[tools]` | `mise bootstrap` |
| macOS settings (Dock, Finder, `defaults`) | `[bootstrap.macos.*]` | `mise bootstrap` |
| oh-my-zsh, powerlevel10k, zsh-autosuggestions | `[bootstrap.repos]` | `mise bootstrap` |
| Config files, symlinked into `~` | `[dotfiles]` | `mise bootstrap`, `mise dot apply` |
| Curl-only tools, druk's themes, secrets, App Store apps on a new Mac | `scripts/post-bootstrap.sh` | `[tasks.bootstrap]`, at the end |
| What only one Mac gets | `config.<profile>.toml` | when that profile is active |

## Layout

| Path | What |
| --- | --- |
| `install.sh` | the entry point of the curl command |
| `config/mise/config.toml` | the shared recipe |
| `config/mise/config.{work,personal}.toml` | each profile's packages, tools, settings, `DOTFILES_PROFILE` and 1Password vault |
| `config/mise/miserc.local.toml` | this Mac's profile; written by `install.sh`, not committed |
| `config/<tool>/` | config files, symlinked into `~` |
| `config/secrets/{shared,<profile>}/<name>.tpl` | templates of secret files: `op://` references, never values |
| `scripts/post-bootstrap.sh` | what mise can't declare |
| `mise.toml` | the project's tasks (`check`, `test:*`) and the tools they use |
| `tests/` | the VM tests and their fake services |

## Make a change

| To add | Do |
| --- | --- |
| a Homebrew package or cask | `mise bootstrap packages use brew:<name>` (or `brew-cask:<name>`); stays `latest` |
| a tool | `mise use -g <tool>@<version>`, always exact; a profile-only tool goes in `config.<profile>.toml` |
| a config file | move it into `config/<tool>/` and add a line under `[dotfiles]` |
| a secret | see [Secrets](#secrets) |
| a step in `post-bootstrap.sh` | safe to repeat; report failures with `warn` (the script always exits 0); run tools with `mise exec <tool> --`; never export `op_token` |

A file that already exists on a Mac is never overwritten silently: rerun with `--force-dotfiles`.

## Check without applying

```bash
mise -E personal bootstrap status     # what differs from the repo
mise -E personal bootstrap --dry-run  # what a run would do
mise -E personal dot status           # only the symlinks
```

- On a Mac that doesn't use this config yet, prefix them with `MISE_CONFIG_DIR=$PWD/config/mise`.
- Turn auto-install off before `mise exec` against this config (`MISE_EXEC_AUTO_INSTALL=false
  MISE_AUTO_INSTALL=false`), or mise first installs every missing tool of the recipe.

## Secrets

| Vault | Holds | Default set in |
| --- | --- | --- |
| `dotfiles` | the shared secrets | `post-bootstrap.sh` (`DOTFILES_OP_VAULT`) |
| `rcrd-dotfiles` | the personal Mac's | `config.personal.toml` (`DOTFILES_OP_PROFILE_VAULT`) |
| `np-dotfiles` | the work Mac's | `config.work.toml` (`DOTFILES_OP_PROFILE_VAULT`) |

- Each Mac has a read-only service account for its two vaults: `dotfiles-personal` or `dotfiles-work`.
  `install.sh` keeps its token in the Keychain item `dotfiles-op` (`DOTFILES_OP_KEYCHAIN_ITEM`).
- `config/secrets/shared/<path>.tpl` and `config/secrets/<profile>/<path>.tpl` become `~/.<path>` (mode 600) on
  every bootstrap, before the steps that use them: `env.tpl` → `~/.env`, `ssh/id_ed25519.tpl` →
  `~/.ssh/id_ed25519`. `post-bootstrap.sh` keeps a list of what it wrote
  (`~/.local/state/dotfiles/secret-files`); any other file in the way is hand-made, and is kept once as
  `~/.<path>.before-dotfiles`. A template that allows comments starts with one saying it's generated.
- The GitHub SSH key is the `github` item (type SSH Key) in `dotfiles`; its public key is on GitHub for both
  authentication and signing. `?ssh-format=openssh` makes `op` write the private key in OpenSSH's format.
- **To add a secret:** create the item in 1Password (title and field as the template will name them), add
  the line, for example `export FOO="{{ op://$DOTFILES_OP_VAULT/foo/credential }}"`, add a fake value to
  `tests/mocks/1password/fixtures/vaults.json`, then `mise run bootstrap`.
- A service account can't change its vaults: for another vault, create a new one
  (`op service-account create <name> --vault <vault>:read_items …`) and replace the token.

## Tool notes

- **Zed, druk:** they rewrite their own config files, which are symlinks into the repo. Review and commit
  those changes.
- **Ardia:** it reads `~/.config/ardia/config.json` and never writes it. `config/ardia/config.json` holds only
  what differs from Ardia's defaults, and wins over Ardia's UI. Every setting and its default:
  `~/Library/Application Support/com.ardia.browser/config-schema/config.schema.json`.
- **SSH:** GitHub's host keys are a mise block in `~/.ssh/known_hosts` (from `config/ssh/known_hosts.github`),
  so a new Mac doesn't ask to trust github.com; ssh keeps writing its own lines around it. If GitHub ever
  rotates them, refresh the file from `gh api meta --jq '.ssh_keys[]'` and check the fingerprints on
  docs.github.com.
- **Claude Code:** `~/.claude` is its own. Only the status line script and the `statusLine` key of
  `settings.json` (merged) come from here.

## Conventions

- Everything mise can install goes through mise, at an exact version. Homebrew can't pin: `latest`.
- Theme: [Vesper](https://github.com/raunofreiberg/vesper) in dark mode, Ayu Light in light mode, following the
  system where the tool allows it. Font: [JetBrains Mono](https://www.jetbrains.com/lp/mono/).
- gitleaks runs before each commit and push (lefthook). `post-bootstrap.sh` installs the hooks; by hand:
  `mise exec lefthook -- lefthook install`. GitHub runs `mise run check` on each push to `main` and each pull
  request (`.github/workflows/check.yml`), and its ruleset only takes signed commits on `main`, never a force
  push. Actions are pinned by commit SHA.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary`,
  for example `feat(zsh): …`, `fix(install): …`, `test: …`, `docs: …`, `chore(deps): …`.

## Tests

From the repo root (its `mise.toml` is the project's own: tasks and the tools they use). Needs an Apple
Silicon Mac and about 30 GB free for the base image.

```bash
mise run check       # static, no VM, seconds: config/mise parses as each Mac, shellcheck, gitleaks, the mock's checks
mise run test:setup  # once: the test tools, the base macOS VM, the fake 1Password's packages
mise run test:func   # install.sh twice on a throwaway VM without the apps (--skip packages), then func/: minutes
mise run test:e2e    # the same with everything, then func/ and e2e/: the test to pass before publishing
```

- `test:func` and `test:e2e` test both Macs, one after the other. `mise run test:func personal` tests one.
- `--published` tests what a new Mac gets: the VM runs `curl -fsSL https://rcrd.space/mac/install.sh | bash`,
  which clones GitHub's `main`, instead of your working tree (the suites still come from it). Run it after
  pushing a change to `install.sh`, `post-bootstrap.sh` or `config/mise`, and before formatting a Mac.
  `TEST_INSTALL_URL` points it elsewhere.
- `--window` opens a window with the VM's desktop to watch it work; `--keep` leaves the VM running at the end.
  Without a window you can still look in with Screen Sharing: `open vnc://admin@<ip>` (password `admin`;
  `tart ip <vm>` gives the address).
- Each run leaves `tests/results/<date>-<mode>-<profile>/`: `report.html` to open, `report.xml`, and the
  logs.

| Path | What |
| --- | --- |
| `tests/mise.toml` | the tools (Tart, bats, junit2html, node, pnpm) and the tasks the root's `test:*` run |
| `tests/run.sh` | the runner: VM, fake 1Password, `install.sh` twice, suites, report |
| `tests/smoke.bats` | the runner's own check: the VM starts clean |
| `tests/func/` | suites for every run: what a Mac gets without the apps |
| `tests/e2e/` | suites only for e2e runs: what needs the apps |
| `tests/mocks/1password/` | the fake 1Password, a project of the `tests/` mise [monorepo](https://mise.jdx.dev/tasks/monorepo.html) |

### What a run does

1. Copies the working tree (what `.gitignore` lets through, uncommitted changes included) into a
   one-commit repo outside the project, which the VM clones.
2. Clones the base VM, boots it without a window, and mounts the copy and bats read-only and the results
   folder writable.
3. Reaches it over SSH with the image's default password (`SSH_ASKPASS`), without touching `~/.ssh`.
4. Starts the fake 1Password on this Mac, on the address the VM sees it at.
5. Checks the VM is clean (`smoke.bats`), then runs `install.sh` twice, piped into bash as `curl | bash`
   does, under time limits (100 and 40 minutes). `func` passes it `--skip packages`.
6. Runs the suites inside the VM in one go (`func/`, plus `e2e/` on e2e runs), then deletes the VM.

### Harness-only behaviour

What the test does that a person at a new Mac doesn't:

- `NONINTERACTIVE=1` for Homebrew's installer, which would wait for Return.
- `DOTFILES_PROFILE` and a made-up `DOTFILES_OP_TOKEN` answer `install.sh`'s questions.
- Unlocks the login Keychain before `install.sh`: over SSH it's locked, in a person's session it isn't.
- Writes a `~/.claude/settings.json` with one key first, to check the `statusLine` merge keeps it.
- Gives mise's cache a disk of its own (a 40 GB sparse image, deleted with the VM): the app installers it keeps
  (about 6 GB) would fill the base image's 18 GB free. It's formatted on this Mac first, so the VM mounts it at
  boot without asking. A shared folder doesn't work for it: it doesn't support the file locks mise takes.
- The VM has no Apple Account, so `MISE_SYSTEM_PACKAGES_MANAGERS=brew,brew-cask` leaves the App Store apps out:
  `mas install` would wait forever at its sign-in window. The warning about them is expected.
- Its SSH key comes from the fake 1Password, which makes a new pair each time it starts, so no private key
  lives in the repo.

### The fake 1Password

With `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` set, `op` talks to a 1Password Connect server, ahead of
`OP_SERVICE_ACCOUNT_TOKEN`. `tests/mocks/1password` is a fake one built with [emulate](https://emulate.dev):
it answers what `op read` and `op inject` ask, from `fixtures/vaults.json` (real names, fake values). It's a
Node project set up like the Variable Lab repos: pnpm and
[run-run](https://github.com/withvariablelab/dx/tree/main/run-run/cli) with Biome, oxlint and Vitest.

```bash
mise -C tests //mocks/1password:start   # serve it on 127.0.0.1:4100, then:
OP_CONNECT_HOST=http://127.0.0.1:4100 OP_CONNECT_TOKEN=x op read op://rcrd-dotfiles/vland-registry/url
```

### Writing tests

- Put a check in `tests/func/` if it holds without the apps, in `tests/e2e/` if it needs them. A file named
  after a profile (`personal.bats`, `work.bats`) runs only for that Mac.
- Suites run inside the VM and `load ../helpers` (`tests/helpers.bash`): `terminal '…'` runs a command as a
  new terminal sees it, `bootstrap_status '<jq>'` queries `mise bootstrap status --json`, `op_read op://…` asks
  1Password (the fake one, in a run) for a value.
- The mounts are under `/Volumes/My Shared Files` (`dotfiles`, `bats`, `results`).

### Disk

- The base VM takes about 28 GB; `tart delete neo-base` removes it (`mise run test:setup` pulls it again).
- A profile run takes about 20 GB more while it runs (the VM's copy and the cache disk) and frees it at the end.
  With `--keep`, they stay until you delete the VM.
- `tart prune --entries=caches --older-than=0` drops Tart's cached images.

## Publishing

`rcrd.space/mac/install.sh` redirects to `https://raw.githubusercontent.com/rqbazan/.dotfiles/main/install.sh`.
