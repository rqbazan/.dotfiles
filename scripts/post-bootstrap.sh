#!/bin/bash
# shellcheck disable=SC2015 # "step && echo ✓ || warn …": echo never fails, so warn runs only when the step does
# Runs at the end of every `mise bootstrap` (see [tasks.bootstrap]).
# Only what Homebrew and mise can't declare. Safe to repeat.
# Optional steps that fail are reported at the end and never stop the rest.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.druk/bin:$PATH"

failed=()
warn() { failed+=("$1"); echo "! $1"; }

# Every project lives here; mise trusts configs under it (trusted_config_paths).
mkdir -p "$HOME/Developer" || warn "could not create ~/Developer"

# 1Password: install.sh keeps this Mac's read-only service account token in the Keychain. It stays in
# a plain variable, never exported, so no other step or installer sees it. Every name can be overridden:
#   DOTFILES_OP_VAULT          vault with the shared items (default: dotfiles)
#   DOTFILES_OP_PROFILE_VAULT  vault with this profile's items (default set in config.<profile>.toml)
#   DOTFILES_OP_KEYCHAIN_ITEM  Keychain item holding the token (default: dotfiles-op)
op_vault="${DOTFILES_OP_VAULT:-dotfiles}"
op_profile_vault="${DOTFILES_OP_PROFILE_VAULT:-}"
op_item="${DOTFILES_OP_KEYCHAIN_ITEM:-dotfiles-op}"
op_token="$(security find-generic-password -s "$op_item" -a "$USER" -w 2>/dev/null || true)"
op_cli() {
  DOTFILES_OP_VAULT="$op_vault" DOTFILES_OP_PROFILE_VAULT="$op_profile_vault" OP_SERVICE_ACCOUNT_TOKEN="$op_token" \
    mise exec 1password-cli -- op "$@"
}
[ -n "$op_token" ] ||
  warn "no 1Password token in the Keychain ($op_item): secrets skipped; run install.sh again to add it"

# Secret files, before anything that uses them (the SSH key, for commit signing below).
# config/secrets/shared/<path>.tpl (items from $DOTFILES_OP_VAULT) and config/secrets/<profile>/<path>.tpl
# (items from $DOTFILES_OP_PROFILE_VAULT) hold only op:// references. Together they become ~/.<path> (mode 600),
# filled in by 1Password: env.tpl → ~/.env, ssh/id_ed25519.tpl → ~/.ssh/id_ed25519. They are the source of
# truth. A file this script hasn't written before (it keeps a list) is hand-made, and is kept once as
# ~/.<path>.before-dotfiles before it is replaced.
secrets="$DOTFILES_DIR/config/secrets"
profile="${DOTFILES_PROFILE:-}" # set by config.<profile>.toml
written="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/secret-files"
if [ -n "$op_token" ]; then
  mkdir -p "$(dirname "$written")" && touch "$written"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  while read -r rel; do
    dest="$HOME/.$rel"
    parts=()
    for scope in shared "$profile"; do
      [ -n "$scope" ] && [ -f "$secrets/$scope/$rel.tpl" ] && parts+=("$secrets/$scope/$rel.tpl")
    done
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && ! grep -qxF "$dest" "$written"; then
      cp -p "$dest" "$dest.before-dotfiles" && echo "- kept your previous ~/.$rel as ~/.$rel.before-dotfiles"
    fi
    if cat "${parts[@]}" | op_cli inject --force --file-mode 0600 -o "$dest" >/dev/null; then
      grep -qxF "$dest" "$written" || echo "$dest" >>"$written"
      echo "✓ ~/.$rel (1Password)"
    else
      warn "$dest was not written: check that vaults $op_vault and ${op_profile_vault:-?} have the items its templates name"
    fi
  done < <(cd "$secrets" && find shared ${profile:+"$profile"} -name '*.tpl' 2>/dev/null |
    sed -E 's#^[^/]+/##; s#\.tpl$##' | sort -u)
fi

# Commit signing: user.signingkey lives in an unversioned file that config/git/config includes. The key
# usually comes from 1Password (config/secrets/shared/ssh), written just above.
GIT_LOCAL="$HOME/.config/git/local"
if [ ! -e "$GIT_LOCAL" ]; then
  for key in "$HOME/.ssh/id_ed25519_signing.pub" "$HOME/.ssh/id_ed25519.pub"; do
    [ -f "$key" ] || continue
    mkdir -p "$(dirname "$GIT_LOCAL")" &&
      printf '[user]\n\tsigningkey = %s\n' "$key" > "$GIT_LOCAL" &&
      echo "✓ $GIT_LOCAL → $key"
    break
  done
  [ -e "$GIT_LOCAL" ] || warn "no SSH key found: create one, then set user.signingkey in $GIT_LOCAL"
fi

# Screenshots folder declared in [bootstrap.macos.defaults].
mkdir -p "$HOME/Pictures/Screenshots" || warn "could not create ~/Pictures/Screenshots"

# Default apps for code files (config/duti/defaults.duti).
if command -v duti >/dev/null 2>&1; then
  duti "$DOTFILES_DIR/config/duti/defaults.duti" && echo "✓ default apps" || warn "duti could not set some default apps"
else
  warn "duti is missing: default apps not set"
fi

# App Store apps: mas comes from [tools], which mise installs after packages, so on a new Mac
# the mas: entries were skipped earlier in this same run. Retry only those (no-op once installed).
if mise which mas >/dev/null 2>&1; then
  mise bootstrap packages apply --manager mas --yes </dev/null && echo "✓ App Store apps" ||
    warn "App Store apps were not installed (is the Apple Account signed in?); run: mise bootstrap packages apply --manager mas"
else
  warn "mas is missing: App Store apps not installed"
fi

# name | installer (each vendor's official one)
while IFS='|' read -r cmd url; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✓ $cmd"
  else
    echo "→ installing $cmd"
    # Download first, so a failed download never runs half a script. Output through a pipe: druk's installer
    # opens /dev/tty when stdout is a terminal, and mise's bootstrap task has no terminal to open.
    if script="$(curl -fsSL --retry 2 "$url")" && bash -c "$script" </dev/null | cat; then
      echo "✓ $cmd"
    else
      warn "$cmd was not installed ($url); run this again later with: mise run bootstrap"
    fi
  fi
done <<'TOOLS'
herdr|https://herdr.dev/install.sh
claude|https://claude.ai/install.sh
opencode|https://opencode.ai/install
druk|https://druk.letstri.dev/install
pi|https://pi.dev/install.sh
TOOLS

# druk's colour themes are extensions: its app installs one by fetching <id>/extension.json from
# druk's registry into ~/.config/druk/extensions. Same here for the two config/druk/config.json uses.
for ext in vesper ayu; do
  dest="$HOME/.config/druk/extensions/$ext/extension.json"
  if [ -s "$dest" ]; then
    echo "✓ druk theme $ext"
  elif mkdir -p "$(dirname "$dest")" &&
    curl -fsSL --retry 2 "https://raw.githubusercontent.com/letstri/druk/main/extensions/$ext/extension.json" -o "$dest.tmp" &&
    mv "$dest.tmp" "$dest"; then
    echo "✓ druk theme $ext"
  else
    rm -f "$dest.tmp"
    warn "druk theme $ext was not installed; install it from druk's extensions panel"
  fi
done

# Personal Mac: pnpm 12 asks vland-registry-token for a fresh gcloud token on every run,
# so the private @variableland registry never needs a stored token. Lives in pnpm's own auth.ini.
# The registry's address stays out of this public repo: it is the item vland-registry (field url,
# host/path without https://) in the profile's vault.
if [ -x "$HOME/.local/bin/vland-registry-token" ] && [ -n "$op_token" ]; then
  if [ -n "$op_profile_vault" ] &&
    registry="$(op_cli read "op://$op_profile_vault/vland-registry/url" 2>/dev/null)" && [ -n "$registry" ]; then
    mise exec pnpm -- pnpm config set "//$registry/:tokenHelper" \
      "$HOME/.local/bin/vland-registry-token" >/dev/null && echo "✓ pnpm tokenHelper (@variableland)" ||
      warn "pnpm tokenHelper for @variableland was not set"
  else
    warn "could not read op://${op_profile_vault:-?}/vland-registry/url from 1Password: pnpm tokenHelper for @variableland not set"
  fi
fi

# Chrome for Testing, the browser agent-browser drives. It keeps it under ~/.agent-browser.
if command -v agent-browser >/dev/null 2>&1; then
  if compgen -G "$HOME/.agent-browser/browsers/chrome-*" >/dev/null; then
    echo "✓ Chrome for Testing"
  else
    echo "→ installing Chrome for Testing"
    agent-browser install </dev/null && echo "✓ Chrome for Testing" || warn "Chrome for Testing was not installed; run: agent-browser install"
  fi
fi

# gitleaks hooks for this repo (only when it is a git checkout)
if git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  (cd "$DOTFILES_DIR" && mise exec lefthook -- lefthook install) || warn "lefthook hooks were not installed"
else
  echo "- $DOTFILES_DIR is not a git checkout: skipping the gitleaks hooks"
fi

if [ "${#failed[@]}" -gt 0 ]; then
  printf '\n%s step(s) need attention:\n' "${#failed[@]}"
  printf '  - %s\n' "${failed[@]}"
fi
# Always 0: none of these steps should mark the whole bootstrap as failed.
exit 0
