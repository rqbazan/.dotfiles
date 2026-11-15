# Shared by the suites in func/ and e2e/ (`load ../helpers`). run.sh sets TEST_MODE (func or e2e),
# DOTFILES_PROFILE, TEST_OP_TOKEN (the made-up token it gave install.sh), and OP_CONNECT_HOST and
# OP_CONNECT_TOKEN, which point op at the fake 1Password.
MOUNTS="/Volumes/My Shared Files"
RESULTS="$MOUNTS/results"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

# What a new terminal sees: a login, interactive zsh.
terminal() { zsh -lic "$1" </dev/null 2>&1; }

# `mise bootstrap status --json`, once per run and kept with the results; $1 is a jq filter over it.
bootstrap_status() {
  local file="$RESULTS/bootstrap-status.json"
  [ -s "$file" ] || mise bootstrap status --json </dev/null >"$file"
  jq -r "$1" "$file"
}

# What 1Password holds for an op:// reference, asked the way post-bootstrap.sh asks.
op_read() { mise exec 1password-cli -- op read "$1"; }

private() { [ "$(stat -f %Lp "$1")" = 600 ]; }

# The warnings listed at the end of install run $1, one per line.
warnings() {
  sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$RESULTS/install-$1.log" |
    awk '/step\(s\) need attention:/ { on = 1; next } on && /^  - / { sub(/^  - /, ""); print; next } { on = 0 }'
}
