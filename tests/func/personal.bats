#!/usr/bin/env bats
# Runs inside the VM after install.sh ran twice as the personal Mac.

load ../helpers

@test "personal: its shell file and the registry's token helper are linked" {
  [ "$(readlink ~/.zshrc.local)" = "$HOME/.dotfiles/config/zsh/zshrc.personal" ]
  [ -x ~/.local/bin/vland-registry-token ]
}

@test "personal: ~/.npmrc has the npm token, private" {
  private ~/.npmrc
  grep -qxF "//registry.npmjs.org/:_authToken=$(op_read op://rcrd-dotfiles/npm/credential)" ~/.npmrc
}

@test "personal: pnpm asks the token helper for the @variableland registry" {
  # pnpm config get hides auth settings: read pnpm's own auth file
  registry="$(op_read op://rcrd-dotfiles/vland-registry/url)"
  grep -qxF "//$registry/:tokenHelper=$HOME/.local/bin/vland-registry-token" ~/Library/Preferences/pnpm/auth.ini
}

@test "personal: projects pick their node and terraform versions" {
  run mise settings get idiomatic_version_file_enable_tools
  [[ "$output" == *node* && "$output" == *terraform* && "$output" != *go* ]]
}
