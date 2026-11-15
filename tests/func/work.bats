#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice as the work Mac.

load ../helpers

@test "work: none of the personal Mac's files" {
  [ ! -e ~/.zshrc.local ]
  [ ! -e ~/.npmrc ]
  [ ! -e ~/.local/bin/vland-registry-token ]
}

@test "work: projects pick their node, go, terraform and opentofu versions" {
  run mise settings get idiomatic_version_file_enable_tools
  [[ "$output" == *node* && "$output" == *go* && "$output" == *terraform* && "$output" == *opentofu* ]]
}
