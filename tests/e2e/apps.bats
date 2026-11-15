#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice with everything: what needs the apps.

load ../helpers

@test "every app and Homebrew package is installed" {
  # mas is left out of the test runs: the VM has no Apple Account
  run bootstrap_status '.packages | to_entries[] | select(.key != "mas") | .value.packages[]? |
    select(.state != "installed") | "\(.package) \(.state)"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "code files open in Zed" {
  [[ "$(duti -x tsx)" == *Zed* ]]
  [[ "$(duti -x toml)" == *Zed* ]]
}

@test "Ghostty accepts its config" {
  /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config
}
