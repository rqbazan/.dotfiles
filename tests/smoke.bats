#!/usr/bin/env bats
# Runs inside the VM, before install.sh. Proves the runner: a clean Mac, the mounts, passwordless sudo and
# the fake 1Password.

MOUNTS="/Volumes/My Shared Files"

@test "the guest is macOS 26.6.2" {
  [ "$(sw_vers -productVersion)" = "26.6.2" ]
}

@test "the repo snapshot is mounted, with install.sh" {
  [ -f "$MOUNTS/dotfiles/install.sh" ]
  [ -d "$MOUNTS/dotfiles/.git" ]
}

@test "the Mac starts empty: no Homebrew, no mise" {
  [ ! -e /opt/homebrew/bin/brew ]
  [ ! -e "$HOME/.local/bin/mise" ]
}

@test "sudo needs no password (install.sh runs unattended)" {
  sudo -n true
}

@test "the results folder is writable from the guest" {
  touch "$MOUNTS/results/.guest-can-write"
}

@test "the fake 1Password answers from the guest, by vault title" {
  [ -n "${OP_CONNECT_HOST:-}" ]
  curl -fsS "$OP_CONNECT_HOST/heartbeat"
  run curl -fsS -H "Authorization: Bearer $OP_CONNECT_TOKEN" --get \
    --data-urlencode 'filter=title eq "rcrd-dotfiles"' "$OP_CONNECT_HOST/v1/vaults"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"rcrd-dotfiles"'* ]]
  [[ "$output" != *'"name":"dotfiles"'* ]] # the filter applies
}
