#!/usr/bin/env bats
# Runs inside the VM. install.sh --help as `curl … | bash -s -- --help` runs it, with the Mac's own bash (3.2):
# the usage, and nothing past it.

load ../helpers

@test "install.sh --help prints the usage and stops there" {
  run /bin/bash -s -- --help <"$MOUNTS/dotfiles/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl -fsSL https://rcrd.space/mac/install.sh | bash"* ]]
  [[ "$output" == *"DOTFILES_PROFILE=work|personal"* ]]
  [[ "$output" != *"1/5"* ]]
}

@test "install.sh prints no colours without a terminal" {
  run /bin/bash -s -- --help <"$MOUNTS/dotfiles/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}
