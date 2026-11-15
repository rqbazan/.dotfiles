#!/bin/bash
# Sets up a Mac from zero, and brings an existing one up to date. Same command:
#
#   curl -fsSL https://rcrd.space/mac/install.sh | bash
#
# This script only gets mise onto the machine and picks a profile; everything
# else is declared in config/mise/config.toml and applied by `mise bootstrap`.
#
#   DOTFILES_PROFILE=work|personal   skip the profile question
#   DOTFILES_REPO=<git url>          clone from somewhere else
#   DOTFILES_OP_TOKEN=<token>        skip the 1Password token question (unattended runs)
#   DOTFILES_OP_VAULT=<vault>        1Password vault with the shared secrets (default: dotfiles)
#   DOTFILES_OP_PROFILE_VAULT=<vault>  vault with the profile's secrets (default in config.<profile>.toml)
#   DOTFILES_OP_KEYCHAIN_ITEM=<name>   Keychain item for the token (default: dotfiles-op)
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/rqbazan/.dotfiles.git}"
DIR="$HOME/.dotfiles"
MISE_DIR="$HOME/.config/mise"
LOCAL_RC="$DIR/config/mise/miserc.local.toml"
OP_KEYCHAIN_ITEM="${DOTFILES_OP_KEYCHAIN_ITEM:-dotfiles-op}" # scripts/post-bootstrap.sh reads the same item

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# The same as min_version in config/mise/config.toml: its lockfiles need it.
MISE_MIN_VERSION="2026.11.8"
mise_is_recent() {
  local version
  version="$(mise --version 2>/dev/null | awk '{print $1}')" && [ -n "$version" ] || return 1
  [ "$(printf '%s\n%s\n' "$MISE_MIN_VERSION" "$version" | sort -V | head -1)" = "$MISE_MIN_VERSION" ]
}

[ "$(uname -s)" = "Darwin" ] || die "macOS only"

# Everything that can stop the run is checked before anything on this Mac changes.
if [ -e "$DIR" ] && ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "$DIR exists but is not a git checkout. Move it away and run this again."
fi

say "1/5 Homebrew"
# Its installer also brings the Xcode Command Line Tools (git).
# stdin is this script when piped from curl, so prompts go to the terminal.
if ! [ -x /opt/homebrew/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

say "2/5 mise"
export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 || curl -fsSL https://mise.run | sh
if ! mise_is_recent; then
  echo "mise $(mise --version 2>/dev/null | awk '{print $1}') is too old for this setup; updating it"
  mise self-update --yes </dev/null || true
  mise_is_recent || die "mise is still too old ($MISE_MIN_VERSION or newer is needed). Update it by hand (mise self-update, or brew upgrade mise) and run this again."
fi
mise --version

say "3/5 Profile"
if [ -f "$LOCAL_RC" ]; then
  profile="" # already chosen on this Mac; mise reads it from the file
  echo "using $LOCAL_RC"
else
  profile="${DOTFILES_PROFILE:-}"
  if [ -z "$profile" ]; then
    read -r -p "Which Mac is this? [work/personal] " profile </dev/tty ||
      die "no terminal to ask on; run this again with DOTFILES_PROFILE=work or DOTFILES_PROFILE=personal"
  fi
  case "$profile" in
    work|personal) ;;
    *) die "unknown profile: '$profile' (use work or personal)" ;;
  esac
fi

if [ -n "$profile" ]; then env_flag=(-E "$profile"); else env_flag=(); fi

say "4/5 1Password"
# Secrets come from 1Password, through this Mac's service account, which can only read its vaults.
# Its token lives in the login Keychain, never in a file, and is asked for once per Mac.
if security find-generic-password -s "$OP_KEYCHAIN_ITEM" -a "$USER" >/dev/null 2>&1; then
  echo "token already in the Keychain ($OP_KEYCHAIN_ITEM)"
else
  token="${DOTFILES_OP_TOKEN:-}"
  if [ -z "$token" ]; then
    read -r -s -p "1Password service account token for this Mac (Enter to skip): " token </dev/tty ||
      token=""
    echo
  fi
  if [ -n "$token" ]; then
    # Through stdin: the -w prompt of `security` cuts input at 128 characters, and an
    # argument would show in ps. printf is a shell builtin, so the token never does.
    # A failure here only costs the secrets, so it warns and the install goes on.
    if printf 'add-generic-password -U -s %s -a %s -w %s\n' "$OP_KEYCHAIN_ITEM" "$USER" "$token" |
      security -i >/dev/null && security find-generic-password -s "$OP_KEYCHAIN_ITEM" -a "$USER" >/dev/null 2>&1; then
      echo "saved in the Keychain ($OP_KEYCHAIN_ITEM)"
    else
      printf '\033[33m! could not save the token in the Keychain: secrets are skipped this time.\n'
      printf '  Run this command again to add it; everything else installs now.\033[0m\n'
    fi
  else
    echo "skipped: secrets are not written until the token is in the Keychain (run this again to add it)"
  fi
  unset token
fi

say "5/5 mise bootstrap"
# mise links ~/.config/mise to the checkout and needs that path free.
backup=""
if [ -d "$MISE_DIR" ] && [ ! -L "$MISE_DIR" ]; then
  backup="$MISE_DIR.before-dotfiles.$(date +%Y%m%d%H%M%S)"
  mv "$MISE_DIR" "$backup"
fi

status=0
mise ${env_flag[@]+"${env_flag[@]}"} bootstrap \
  --from "$REPO" --from-dir "$DIR" --config-dir config/mise \
  --update --skip-dirty --yes "$@" || status=$?

# Remember the choice as soon as the checkout is linked, so a later plain
# `mise bootstrap` uses the right profile even if this run stopped halfway.
if [ -n "$profile" ] && [ -L "$MISE_DIR" ] && [ -d "$DIR/config/mise" ] && [ ! -f "$LOCAL_RC" ]; then
  printf 'env = ["%s"]\n' "$profile" > "$LOCAL_RC"
fi

if [ "$status" -ne 0 ]; then
  # mise stopped before linking its config: put the previous one back.
  if [ -n "$backup" ] && [ ! -e "$MISE_DIR" ] && [ ! -L "$MISE_DIR" ]; then
    mv "$backup" "$MISE_DIR"
    echo "restored $MISE_DIR" >&2
  elif [ -n "$backup" ]; then
    echo "your previous mise config is in $backup" >&2
  fi
  die "mise bootstrap failed (exit $status). Fix what it reported and run this again; it is safe to repeat."
fi

[ -z "$backup" ] || echo "previous mise config kept in $backup"
say "Done. Open a new terminal."
