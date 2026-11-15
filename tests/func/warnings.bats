#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice. The list of warnings it ends with holds only what a VM
# can't do.

load ../helpers

@test "the second run warns only about what a VM can't do" {
  expected='^App Store apps were not installed' # no Apple Account
  [ "$TEST_MODE" = func ] && expected="$expected|^duti is missing" # duti is a Homebrew package
  run warnings 2
  [ "$status" -eq 0 ]
  unexpected="$(grep -vE "$expected" <<<"$output" || true)"
  [ -z "$unexpected" ] || { echo "unexpected warnings:"; echo "$unexpected"; false; }
}

@test "the first run saved the token without asking" {
  grep -qF "saved in the Keychain (dotfiles-op)" "$RESULTS/install-1.log"
}
