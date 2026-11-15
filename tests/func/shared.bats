#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice. What every Mac gets, whatever its profile, apps aside.

load ../helpers

@test "install.sh succeeded both times" {
  [ "$(cat "$RESULTS/install-1.exit")" = 0 ]
  [ "$(cat "$RESULTS/install-2.exit")" = 0 ]
}

@test "the repo is a checkout at ~/.dotfiles, and it is mise's global config" {
  git -C ~/.dotfiles rev-parse --is-inside-work-tree
  [ "$(cd ~/.config/mise && pwd -P)" = "$(cd ~/.dotfiles/config/mise && pwd -P)" ]
  grep -qF "\"$DOTFILES_PROFILE\"" ~/.dotfiles/config/mise/miserc.local.toml
}

@test "every tool in config/mise is installed" {
  run bootstrap_status '.tools[] | select(.state != "installed") | "\(.tool) \(.state)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every dotfile is in place" {
  run bootstrap_status '(.dotfiles.files[] | select(.state != "applied") | "\(.target) \(.state)"),
    (.dotfiles.edits[] | select(.state != "applied") | "\(.path) \(.state)")'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "every macOS setting is set" {
  run bootstrap_status '.macos_defaults.entries[] | select(.state != "set") | "\(.domain) \(.key) \(.state)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "oh-my-zsh and its plugins are cloned" {
  run bootstrap_status '.repos[] | select(.state != "current") | "\(.path) \(.state)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a new terminal opens without errors" {
  run script -q /dev/null zsh -lic exit
  [ "$status" -eq 0 ]
  if grep -qiE 'error|not found|no such file|insecure' <<<"$output"; then
    echo "$output"
    false
  fi
}

@test "a new terminal has every command" {
  # shellcheck disable=SC2016 # expands in that zsh
  run terminal 'for c in mise node bun pnpm gh lazygit hunk gitleaks op claude opencode herdr druk pi; do
    command -v $c >/dev/null || echo "missing: $c"; done'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "git pages with hunk" {
  [ "$(git config --get core.pager)" = "hunk pager" ]
}

@test "secret files come from 1Password, private" {
  private ~/.env
  grep -qxF "export CONTEXT7_API_KEY=\"$(op_read op://dotfiles/context7/credential)\"" ~/.env
  if grep -q 'op://' ~/.env; then false; fi
}

@test "the GitHub SSH key comes from 1Password, and git signs with it" {
  private ~/.ssh/id_ed25519
  [ "$(ssh-keygen -y -f ~/.ssh/id_ed25519 | cut -d' ' -f1-2)" = "$(cut -d' ' -f1-2 ~/.ssh/id_ed25519.pub)" ]
  [ "$(git config --get user.signingkey)" = "$HOME/.ssh/id_ed25519.pub" ]
  repo="$BATS_TEST_TMPDIR/signed"
  git init -q "$repo"
  git -C "$repo" commit -q --allow-empty -m signed # commit.gpgsign is on: this fails if it can't sign
  git -C "$repo" cat-file commit HEAD | grep -q 'BEGIN SSH SIGNATURE'
}

@test "github.com is trusted without asking" {
  # The fake key isn't on GitHub: getting as far as "Permission denied" means the host key was known.
  run ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -T git@github.com
  [[ "$output" == *"Permission denied (publickey)"* ]]
}

@test "the 1Password token is in the Keychain, whole" {
  security unlock-keychain -p admin ~/Library/Keychains/login.keychain-db # over SSH it's locked
  [ "$(security find-generic-password -s dotfiles-op -a "$USER" -w)" = "$TEST_OP_TOKEN" ]
}

@test "Claude Code's settings keep their keys and gain the status line" {
  jq -e '.keepMe == true and .statusLine.command == "sh ~/.claude/statusline.sh"' ~/.claude/settings.json
  [ -x ~/.claude/statusline.sh ]
}

@test "druk has its two themes" {
  for ext in vesper ayu; do jq -e .name ~/.config/druk/extensions/$ext/extension.json; done
}

@test "the repo has its gitleaks hooks" {
  [ -x ~/.dotfiles/.git/hooks/pre-commit ]
  [ -x ~/.dotfiles/.git/hooks/pre-push ]
}

@test "nothing wrote into the repo" {
  run git -C ~/.dotfiles status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
