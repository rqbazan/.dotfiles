#!/bin/bash
# The test runner: install.sh on a throwaway macOS VM (Tart), checked with bats. From the repo root:
#
#   mise run test:func   install.sh twice without the apps (--skip packages), as each Mac, then func/: minutes
#   mise run test:e2e    install.sh twice with everything, as each Mac, then func/ and e2e/: about an hour each
#
# Both take a profile (personal or work) to test only that Mac; `run.sh smoke` boots a VM and checks it's clean.
# A suite named after a profile (func/personal.bats) runs only for that Mac.
# --keep leaves the VM (and the snapshot it mounts) running; --window shows its desktop.
# Each run leaves results/<date>-<mode>-<profile>/: report.html (open it), report.xml (JUnit) and the logs.
# 1Password is faked: tests/mocks/1password serves a fake Connect server on this Mac, and the guest's
# `op` reaches it through OP_CONNECT_HOST, so no real account or vault is involved.
set -euo pipefail

# A long install shouldn't stop because this Mac went to sleep.
if [ -z "${TEST_CAFFEINATED:-}" ]; then TEST_CAFFEINATED=1 exec caffeinate -i "$0" "$@"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/.." && pwd)"
MOCK_1PASSWORD="$HERE/mocks/1password"
BASE_VM="${TEST_BASE_VM:-neo-base}" # tests/mise.toml sets it
MOUNTS="/Volumes/My Shared Files"  # where Tart mounts --dir folders inside a macOS guest
FAKE_1PASSWORD_PORT=4100
FAKE_CONNECT_TOKEN="fake-connect-token"                 # the mock only checks that a bearer token is sent
# What install.sh keeps in the guest's Keychain: as long as a real token (about 820 characters), so a step
# that cuts it short shows. The mock ignores it: with OP_CONNECT_HOST set, op talks to the mock instead.
FAKE_SERVICE_ACCOUNT_TOKEN="fake-$(printf '%0816d' 0)"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
# macOS has no `timeout`: perl's alarm ends the command after $1 seconds.
with_timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }

usage="usage: $0 smoke | func [personal|work] | e2e [personal|work]  [--keep] [--window]"
mode="${1:-}"
[ $# -gt 0 ] && shift
profile=""
case "$mode" in
  smoke) ;;
  func | e2e)
    case "${1:-}" in
      personal | work) profile="$1" && shift ;;
      "" | --*) # no profile: both, one after the other
        all=0
        for each in personal work; do "$0" "$mode" "$each" "$@" || all=1; done
        exit "$all"
        ;;
      *) die "$usage" ;;
    esac
    ;;
  *) die "$usage" ;;
esac
keep=false # --keep: leave the VM running at the end, to look around in it
graphics=(--no-graphics)
for arg in "$@"; do
  case "$arg" in
    --keep) keep=true ;;
    --window) graphics=() ;; # open a window with the VM's desktop, to watch it work
    *) die "$usage" ;;
  esac
done
# The suites, relative to tests/. smoke.bats checks a clean Mac, so an install run runs it before installing.
suites=()
if [ -n "$profile" ]; then
  dirs=(func)
  [ "$mode" = e2e ] && dirs+=(e2e)
  for dir in "${dirs[@]}"; do
    for file in "$HERE/$dir"/*.bats; do
      [ -f "$file" ] || continue
      suite="$(basename "$file" .bats)"
      case "$suite" in personal | work) [ "$suite" = "$profile" ] || continue ;; esac
      suites+=("$dir/$suite.bats")
    done
  done
else
  suites=(smoke.bats)
fi
# func skips the apps (mise bootstrap's packages step): minutes instead of half an hour, and a few GB
install_args=()
[ "$mode" = func ] && install_args=(--skip packages)

for tool in tart bats; do
  command -v "$tool" >/dev/null || die "$tool missing: from the repo root, mise run test:setup"
done
mock_node="$(cd "$MOCK_1PASSWORD" && mise which node 2>/dev/null)" || mock_node=""
[ -x "$mock_node" ] && [ -f "$MOCK_1PASSWORD/node_modules/emulate/dist/index.js" ] ||
  die "the 1Password mock isn't set up: from the repo root, mise run test:setup"
tart list --quiet | grep -x "$BASE_VM" >/dev/null || die "no $BASE_VM VM: from the repo root, mise run test:setup"

stamp="$(date +%Y%m%d-%H%M%S)"
name="$mode${profile:+-$profile}"
vm="neo-$name-$stamp"
results="$HERE/results/$stamp-$name"
work="$(mktemp -d)"
mkdir -p "$results"
tart_pid=""
emulate_pid=""
status=0

cleanup() {
  local exit_status=$?
  [ "$status" -ne 0 ] && exit_status="$status"
  if [ -n "$emulate_pid" ]; then
    kill "$emulate_pid" 2>/dev/null || true
    wait "$emulate_pid" 2>/dev/null || true
  fi
  if $keep && [ -n "$tart_pid" ]; then
    printf '\nVM kept: %s, ip %s, user and password admin.\n' "$vm" "${ip:-?}"
    printf '  The snapshot it mounts stays in %s.\n' "$work"
    printf '  When done: tart stop %s && tart delete %s && rm -rf %s\n' "$vm" "$vm" "$work"
  else
    if [ -n "$tart_pid" ]; then
      tart stop --timeout 30 "$vm" >/dev/null 2>&1 || true
      wait "$tart_pid" 2>/dev/null || true
      tart delete "$vm" >/dev/null 2>&1 || true
    fi
    rm -rf "$work"
  fi
  if [ -f "$results/report.xml" ] && command -v junit2html >/dev/null; then
    junit2html "$results/report.xml" "$results/report.html" >/dev/null 2>&1 || true
  fi
  printf '\nResults: %s\n' "$results"
  [ -f "$results/report.html" ] && printf 'Report:  open %s\n' "$results/report.html"
  exit "$exit_status"
}
trap cleanup EXIT

# The VM installs by cloning a git repo, so it gets a one-commit copy of the working tree:
# only what the repo's .gitignore lets through, uncommitted changes included. This never
# touches the project's own history.
say "Snapshot of $REPO_DIR"
rsync -a --exclude .git --exclude tests/results --exclude node_modules "$REPO_DIR/" "$work/tree/"
git -C "$work/tree" init -q -b main
git -C "$work/tree" add -A
git -C "$work/tree" -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false \
  commit -q -m "test snapshot"
git clone -q "$work/tree" "$work/dotfiles" # a clean checkout: committed files only
echo "✓ $(git -C "$work/dotfiles" rev-parse --short HEAD), $(git -C "$work/dotfiles" ls-files | wc -l | tr -d ' ') files"

# The guest's password is the image's public default; SSH_ASKPASS types it, so no sshpass.
# -F /dev/null ignores ~/.ssh/config and UserKnownHostsFile=/dev/null leaves ~/.ssh untouched.
printf '#!/bin/sh\necho admin\n' >"$work/askpass"
chmod 700 "$work/askpass"
export SSH_ASKPASS="$work/askpass" SSH_ASKPASS_REQUIRE=force
ssh_opts=(-F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
  -o PubkeyAuthentication=no -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=6)
# shellcheck disable=SC2029 # the caller builds the remote command on purpose
vm_ssh() { ssh "${ssh_opts[@]}" "admin@$ip" "$@"; }

say "Boot $vm"
tart clone "$BASE_VM" "$vm"
# Profile runs give mise's cache a disk of its own: the app installers it keeps (about 6 GB) would fill the
# base image's 18 GB free. A sparse image takes only what's written, and goes away with the VM.
extra_disk=()
if [ -n "$profile" ]; then
  mkfile -n 40g "$work/mise-cache.img"
  # Formatted here, so the guest mounts it at boot: a blank disk makes macOS ask what to do with it.
  disk_dev="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$work/mise-cache.img" | awk 'NR == 1 {print $1}')"
  if diskutil eraseDisk APFS MiseCache GPT "$disk_dev" >/dev/null; then
    hdiutil detach "$disk_dev" >/dev/null
  else
    hdiutil detach "$disk_dev" >/dev/null 2>&1 || true
    die "could not format the disk for mise's cache"
  fi
  extra_disk=(--disk="$work/mise-cache.img")
fi
tart run ${graphics[@]+"${graphics[@]}"} \
  --dir="dotfiles:$work/dotfiles:ro" \
  --dir="bats:$(cd "$(dirname "$(mise which bats)")/.." && pwd):ro" \
  --dir="results:$results" \
  ${extra_disk[@]+"${extra_disk[@]}"} \
  "$vm" >"$results/tart-run.log" 2>&1 &
tart_pid=$!
ip="$(tart ip --wait 180 "$vm")" || die "the VM got no IP in 180s (see $results/tart-run.log)"
echo "✓ ip $ip"

say "SSH"
for _ in $(seq 1 36); do
  vm_ssh true 2>/dev/null && break
  sleep 5
done
vm_ssh true || die "no SSH to $ip after 3 minutes"
# shellcheck disable=SC2016 # expands in the guest
vm_ssh 'echo "macOS $(sw_vers -productVersion)"; xcode-select -p 2>&1 | sed "s/^/xcode-select -p: /"; df -h / | tail -1 | sed "s/^/disk: /"' |
  tee "$results/guest-info.txt"

# Listen only on the address the guest sees this Mac at (its default gateway on Tart's network),
# not on every interface. node is exec'd directly so that stopping it stops the server (npx, pnpm and
# mise exec would each leave it running as a child).
say "Fake 1Password"
# shellcheck disable=SC2016 # expands in the guest
host_ip="$(vm_ssh 'route -n get default | awk "/gateway/ {print \$2}"')"
[ -n "$host_ip" ] || die "could not find this Mac's address on the VM network"
(cd "$MOCK_1PASSWORD" && exec "$mock_node" node_modules/emulate/dist/index.js start --config emulate.config.ts \
  --host "$host_ip" --port "$FAKE_1PASSWORD_PORT") >"$results/emulate.log" 2>&1 &
emulate_pid=$!
op_connect_host="http://$host_ip:$FAKE_1PASSWORD_PORT"
curl -fs --retry 20 --retry-connrefused --retry-delay 1 "$op_connect_host/heartbeat" >/dev/null ||
  die "the fake 1Password server did not start (see $results/emulate.log)"
echo "✓ $op_connect_host"

# Runs the given suites (paths relative to tests/) inside the guest, in one bats call: one JUnit report in <out>.
run_bats() {
  local out="$1" files=() suite
  shift
  for suite in "$@"; do files+=("\"$MOUNTS/dotfiles/tests/$suite\""); done
  vm_ssh "mkdir -p \"$MOUNTS/results/$out\""
  # pretty output needs a TERM, which a command run over ssh doesn't get
  vm_ssh "TERM=xterm-256color TEST_MODE=$mode DOTFILES_PROFILE=$profile TEST_OP_TOKEN=$FAKE_SERVICE_ACCOUNT_TOKEN \
OP_CONNECT_HOST=$op_connect_host \
OP_CONNECT_TOKEN=$FAKE_CONNECT_TOKEN \"$MOUNTS/bats/bin/bats\" --formatter pretty --report-formatter junit \
--output \"$MOUNTS/results/$out\" ${files[*]}"
}

# install.sh piped into bash, as `curl … | bash` runs it, with a terminal (-tt) as a person has.
# Each run leaves install-<n>.log, .exit and .seconds; a failure goes on to the tests, which report it.
# Harness only:
# - over SSH the login Keychain is locked (a person runs this in their own unlocked session), so the same SSH
#   command first unlocks it with the image's default password;
# - the VM has no Apple Account, and `mas install` would wait forever at the App Store's sign-in window, so
#   MISE_SYSTEM_PACKAGES_MANAGERS leaves mas out (its entries show as skipped).
install_run() {
  local n="$1" secs="$2" start=$SECONDS run_status
  say "install.sh, run $n (up to $((secs / 60)) min)"
  set +e
  with_timeout "$secs" ssh "${ssh_opts[@]}" -tt "admin@$ip" \
    "security unlock-keychain -p admin ~/Library/Keychains/login.keychain-db && \
cat \"$MOUNTS/dotfiles/install.sh\" | DOTFILES_REPO=\"$MOUNTS/dotfiles\" DOTFILES_PROFILE=$profile \
DOTFILES_OP_TOKEN=$FAKE_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST=$op_connect_host OP_CONNECT_TOKEN=$FAKE_CONNECT_TOKEN \
MISE_SYSTEM_PACKAGES_MANAGERS=brew,brew-cask NONINTERACTIVE=1 bash -s -- ${install_args[*]:-}" 2>&1 |
    tee "$results/install-$n.log"
  run_status=${PIPESTATUS[0]}
  set -e
  echo "$run_status" >"$results/install-$n.exit"
  echo "$((SECONDS - start))" >"$results/install-$n.seconds"
  [ "$run_status" -eq 142 ] && echo "✗ timed out after $((secs / 60)) min"
  printf '→ run %s: exit %s in %s min\n' "$n" "$run_status" "$(((SECONDS - start) / 60))"
  [ "$run_status" -eq 0 ] || status=1
}

if [ -n "$profile" ]; then
  say "Precheck: a clean Mac"
  set +e
  run_bats precheck smoke.bats 2>&1 | tee "$results/precheck.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
  set -e

  say "Prepare the guest"
  # A settings.json Claude Code already wrote: the statusLine merge must keep what's in it.
  vm_ssh 'mkdir -p ~/.claude && printf "{\"keepMe\": true}\n" > ~/.claude/settings.json' && echo "✓ ~/.claude/settings.json"
  # Harness only: point mise's cache at the extra disk, which the guest mounted at boot. A real disk, unlike a
  # shared folder, supports the file locks mise takes. Its root belongs to root, so it's handed to the user.
  if vm_ssh '[ -d /Volumes/MiseCache ] && sudo chown admin /Volumes/MiseCache &&
mkdir -p ~/Library/Caches && ln -s /Volumes/MiseCache ~/Library/Caches/mise && touch ~/Library/Caches/mise/.writable'; then
    echo "✓ ~/Library/Caches/mise → its own 40 GB disk"
  else
    die "could not set up the disk for mise's cache"
  fi
  install_run 1 $((100 * 60))
  install_run 2 $((40 * 60))
  vm_ssh 'df -h / | tail -1' | sed 's/^/disk after: /' | tee -a "$results/guest-info.txt"
fi

say "Tests"
set +e
run_bats . "${suites[@]}" 2>&1 | tee "$results/tests.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
set -e
