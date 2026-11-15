#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice. Running it again is how a Mac stays up to date, so the
# second run must find everything in place.

load ../helpers

@test "the second run keeps the token it has" {
  grep -qF "token already in the Keychain (dotfiles-op)" "$RESULTS/install-2.log"
}

@test "the second run is quick: everything is in place" {
  [ "$(cat "$RESULTS/install-2.seconds")" -lt 120 ]
}

@test "the second run warns about the same things as the first" {
  [ "$(warnings 1)" = "$(warnings 2)" ]
}

@test "secret files are rewritten, never kept as if hand-made" {
  if compgen -G "$HOME/.*.before-dotfiles" || compgen -G "$HOME/.ssh/*.before-dotfiles"; then false; fi
  written="$HOME/.local/state/dotfiles/secret-files"
  [ -s "$written" ]
  [ -z "$(sort "$written" | uniq -d)" ]
}
