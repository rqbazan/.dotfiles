#!/bin/bash
# Sets up a Mac from zero, and brings an existing one up to date. Same command:
#
#   curl -fsSL https://rcrd.space/mac/install.sh | bash
#   curl -fsSL https://rcrd.space/mac/install.sh | bash -s -- --help   # its options and variables
#
# This script only gets mise onto the machine and picks a profile; everything
# else is declared in config/mise/config.toml and applied by `mise bootstrap`.
# The variables it reads are listed in usage(), below.
# A new Mac runs it with its own /bin/bash, 3.2: nothing from bash 4 or later.
set -euo pipefail

URL="https://rcrd.space/mac/install.sh"
REPO="${DOTFILES_REPO:-https://github.com/rqbazan/.dotfiles.git}"
DIR="$HOME/.dotfiles"
MISE_DIR="$HOME/.config/mise"
LOCAL_RC="$DIR/config/mise/miserc.local.toml"
OP_KEYCHAIN_ITEM="${DOTFILES_OP_KEYCHAIN_ITEM:-dotfiles-op}" # scripts/post-bootstrap.sh reads the same item

# Colours only on a terminal and never with NO_COLOR. `curl | bash` still prints to the terminal: only its
# stdin is the pipe. On a dark terminal, Vesper's peach, mint and red; on a light one, which Vesper's can't be
# read on, darker ones of the same hues (.github/readme/banner-light.svg uses the same accent). A Mac's
# terminal follows the system's appearance: Terminal.app's default profile does, and so does Ghostty here.
# 24-bit where the terminal says so, else 256 colours.
colors_on() { [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }
if [ "$(uname -s)" = Darwin ] && [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" != Dark ]; then
  rgb=("201;106;34" "31;138;107" "209;77;77") c256=(166 29 167) # light: #C96A22 #1F8A6B #D14D4D
else
  rgb=("255;199;153" "153;255;228" "255;128;128") c256=(223 122 210) # dark, Vesper: #FFC799 #99FFE4 #FF8080
fi
case "${COLORTERM:-}" in
  truecolor | 24bit) for i in 0 1 2; do rgb[i]=$'\033[38;2;'"${rgb[i]}m"; done ;;
  *) for i in 0 1 2; do rgb[i]=$'\033[38;5;'"${c256[i]}m"; done ;;
esac
ACCENT="${rgb[0]}" ACCENT2="${rgb[1]}" RED="${rgb[2]}"
BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
if colors_on 2; then ERR="$RED" ERR_RESET="$RESET"; else ERR="" ERR_RESET=""; fi # die writes to stderr
colors_on 1 || ACCENT="" ACCENT2="" BOLD="" DIM="" RESET=""

say() { printf '\n%s▸ %s%s  %s%s%s\n' "$ACCENT2" "$1" "$RESET" "$BOLD" "$2" "$RESET"; } # say 1/5 Homebrew
ok() { printf '%s✓%s %s\n' "$ACCENT2" "$RESET" "$1"; }
warn() { printf '%s! %s%s\n' "$ACCENT" "$1" "$RESET"; }
die() { printf '\n%s✗ %s%s\n' "$ERR" "$1" "$ERR_RESET" >&2; exit 1; }

# figlet -f "ANSI Shadow" RCRD; .github/readme/banner-{dark,light}.svg draw the same
banner() {
  printf '%s' "$ACCENT"
  cat <<'EOF'
██████╗  ██████╗██████╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗
██████╔╝██║     ██████╔╝██║  ██║
██╔══██╗██║     ██╔══██╗██║  ██║
██║  ██║╚██████╗██║  ██║██████╔╝
EOF
  printf '╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═════╝%s %srcrd.space/mac%s\n\n' "$RESET" "$DIM" "$RESET"
  printf '%sMy Mac, declared: one command sets it up and keeps it up to date.%s\n' "$DIM" "$RESET"
}

usage() {
  local h="$ACCENT$BOLD" r="$RESET"
  row() { printf '  %s%-34s%s %s\n' "$ACCENT2" "$1" "$RESET" "$2"; }
  banner
  printf '\n%sUsage%s\n' "$h" "$r"
  printf '  curl -fsSL %s | bash\n' "$URL"
  printf '  curl -fsSL %s | bash -s -- %s[options]%s\n' "$URL" "$ACCENT2" "$r"
  printf '\n%sOptions%s\n' "$h" "$r"
  row "-h, --help" "show this help, and change nothing"
  row "<anything else>" "goes to mise bootstrap: --skip packages, …"
  printf '\n%sEnvironment%s\n' "$h" "$r"
  row "DOTFILES_PROFILE=work|personal" "skip the profile question"
  row "DOTFILES_REPO=<git url>" "clone from somewhere else"
  row "DOTFILES_OP_TOKEN=<token>" "skip the 1Password question (unattended)"
  row "DOTFILES_OP_VAULT=<vault>" "shared secrets' vault (default: dotfiles)"
  row "DOTFILES_OP_PROFILE_VAULT=<vault>" "profile's vault (default: per profile)"
  row "DOTFILES_OP_KEYCHAIN_ITEM=<name>" "token's Keychain item (default: dotfiles-op)"
  row "NO_COLOR=1" "plain output"
  printf '\n  %se.g.%s curl -fsSL %s | DOTFILES_PROFILE=work bash\n' "$DIM" "$r" "$URL"
  printf '\n%sSteps%s\n' "$h" "$r"
  printf '  Homebrew → mise → profile → 1Password → mise bootstrap. Safe to run again.\n'
}

# The same as min_version in config/mise/config.toml: its lockfiles need it.
MISE_MIN_VERSION="2026.11.8"
mise_is_recent() {
  local version
  version="$(mise --version 2>/dev/null | awk '{print $1}')" && [ -n "$version" ] || return 1
  [ "$(printf '%s\n%s\n' "$MISE_MIN_VERSION" "$version" | sort -V | head -1)" = "$MISE_MIN_VERSION" ]
}

# Before anything else, on any machine: --help only prints.
for arg in "$@"; do
  case "$arg" in -h | --help) usage; exit 0 ;; esac
done

banner

[ "$(uname -s)" = "Darwin" ] || die "macOS only"

# Everything that can stop the run is checked before anything on this Mac changes.
if [ -e "$DIR" ] && ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "$DIR exists but is not a git checkout. Move it away and run this again."
fi

say 1/5 Homebrew
# Its installer also brings the Xcode Command Line Tools (git).
# stdin is this script when piped from curl, so prompts go to the terminal.
if ! [ -x /opt/homebrew/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
ok "$(brew --version | awk 'NR == 1')"

say 2/5 mise
export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 || curl -fsSL https://mise.run | sh
if ! mise_is_recent; then
  echo "→ mise $(mise --version 2>/dev/null | awk '{print $1}') is too old for this setup; updating it"
  mise self-update --yes </dev/null || true
  mise_is_recent || die "mise is still too old ($MISE_MIN_VERSION or newer is needed). Update it by hand (mise self-update, or brew upgrade mise) and run this again."
fi
ok "mise $(mise --version)"

say 3/5 Profile
if [ -f "$LOCAL_RC" ]; then
  profile="" # already chosen on this Mac; mise reads it from the file
  ok "using $LOCAL_RC"
else
  profile="${DOTFILES_PROFILE:-}"
  if [ -z "$profile" ]; then
    read -r -p "${ACCENT2}?${RESET} Which Mac is this? ${DIM}[work/personal]${RESET} " profile </dev/tty ||
      die "no terminal to ask on; run this again with DOTFILES_PROFILE=work or DOTFILES_PROFILE=personal"
  fi
  case "$profile" in
    work|personal) ;;
    *) die "unknown profile: '$profile' (use work or personal)" ;;
  esac
  ok "the $profile Mac"
fi

if [ -n "$profile" ]; then env_flag=(-E "$profile"); else env_flag=(); fi

say 4/5 1Password
# Secrets come from 1Password, through this Mac's service account, which can only read its vaults.
# Its token lives in the login Keychain, never in a file, and is asked for once per Mac.
if security find-generic-password -s "$OP_KEYCHAIN_ITEM" -a "$USER" >/dev/null 2>&1; then
  ok "token already in the Keychain ($OP_KEYCHAIN_ITEM)"
else
  token="${DOTFILES_OP_TOKEN:-}"
  if [ -z "$token" ]; then
    read -r -s -p "${ACCENT2}?${RESET} 1Password service account token for this Mac ${DIM}(Enter to skip)${RESET}: " token </dev/tty ||
      token=""
    echo
  fi
  if [ -n "$token" ]; then
    # Through stdin: the -w prompt of `security` cuts input at 128 characters, and an
    # argument would show in ps. printf is a shell builtin, so the token never does.
    # A failure here only costs the secrets, so it warns and the install goes on.
    if printf 'add-generic-password -U -s %s -a %s -w %s\n' "$OP_KEYCHAIN_ITEM" "$USER" "$token" |
      security -i >/dev/null && security find-generic-password -s "$OP_KEYCHAIN_ITEM" -a "$USER" >/dev/null 2>&1; then
      ok "saved in the Keychain ($OP_KEYCHAIN_ITEM)"
    else
      warn "could not save the token in the Keychain: secrets are skipped this time."
      echo "  Run this command again to add it; everything else installs now."
    fi
  else
    warn "skipped: secrets are not written until the token is in the Keychain (run this again to add it)"
  fi
  unset token
fi

say 5/5 "mise bootstrap"
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

[ -z "$backup" ] || echo "- previous mise config kept in $backup"
printf '\n%s%s✓ Done.%s Open a new terminal.\n' "$ACCENT2" "$BOLD" "$RESET"
