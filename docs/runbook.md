# Runbook

What you do by hand around the one command, in order.

## Before formatting a Mac

- [ ] **Ardia:** copy the recovery phrase (Ardia's Recovery Kit) into 1Password, in `Private`. Without it,
      the synced bookmarks, history, tabs and passwords can't be opened on another Mac.
- [ ] **Ardia:** don't format until another Mac has restored the sync with that phrase.
- [ ] Push every repo under `~/Developer`.

## Before running the command

- [ ] During macOS setup, sign in with your Apple Account and leave iCloud Drive on: Ardia's sync needs it.
- [ ] Open the App Store and check you're signed in there too. If not, the install stops at the App Store's
      sign-in window and waits for you there, with nothing in the terminal saying why.
- [ ] Have your phone with 1Password: the command asks for this Mac's token, the item you saved in `Private`
      for `dotfiles-personal` or `dotfiles-work`.
- [ ] Be on a network without a data cap: the first run downloads several GB.

## Run it

```bash
curl -fsSL https://rcrd.space/mac/install.sh | bash
```

It asks for:

1. your password, then Return (Homebrew);
2. which Mac this is: `work` or `personal`;
3. the 1Password token. Copy it on your phone and paste it on the Mac: with the same Apple Account on both,
   the Mac pastes what the phone just copied. It isn't shown. Enter skips it, and the secrets wait until you
   run the command again.

When it ends, read the list under "step(s) need attention" (see [Warnings](#warnings)).

## After the command

- [ ] Open a new terminal. Your GitHub SSH key is already in `~/.ssh`, from 1Password, and git signs with it.
- [ ] `gh auth login`. Never `gh auth setup-git`: gh already uses SSH, and it would write into this repo.
- [ ] **App Store apps:** if they were skipped, sign in to the App Store, then `mise run bootstrap`.
- [ ] **Ardia:** wait until `Ardia Sync` shows up in iCloud Drive. Then, in each profile, turn sync on, pick
      that folder and enter the recovery phrase. Sign in again to sites and connected accounts.
- [ ] **Personal Mac:** `gcloud auth login`, so pnpm can reach the `@variableland` registry.
- [ ] **Rex:** install it by hand (beta invite, no cask).

## Warnings

| Warning | What to do |
| --- | --- |
| no SSH key found | the token is missing, or the `github` SSH key isn't in 1Password: fix it, then `mise run bootstrap` |
| App Store apps were not installed | sign in to the App Store, then `mise run bootstrap` |
| no 1Password token in the Keychain | run the install command again and paste the token |
| could not save the token in the Keychain | run the install command again |
| `~/.<name>` was not written | a 1Password item a template names is missing (see [Secrets](#change-or-add-a-secret)) |
| `<tool>` was not installed | usually the network: `mise run bootstrap` |
| druk theme was not installed | `mise run bootstrap`, or install it from druk's extensions panel |

`mise run bootstrap` repeats only the last steps (curl-only tools, secrets, App Store apps); the install
command, or `mise bootstrap --update`, repeats everything. Both are safe to run again.

**If an app fails to install, nothing after the apps runs:** no config files, tools or secrets. That's how
mise works ("a run is a sequence, not a transaction"). Fix the cause, or remove the app from `config/mise`,
and run the command again. Meanwhile, `mise bootstrap --skip packages` applies everything else.

## Chores

### Keep a Mac up to date

Run the install command again, or `mise bootstrap --update`. Config files are symlinks into the repo:
editing `~/.zshrc` edits `config/zsh/zshrc`. Commit and push on one Mac, then update the other.

```bash
mise bootstrap status   # what differs from the repo
mise dot status         # only the symlinks
```

### Change or add a secret

Secrets live in 1Password: the shared ones in the `dotfiles` vault, each Mac's in `rcrd-dotfiles` (personal)
or `np-dotfiles` (work). Change a value there and run `mise run bootstrap`. Never edit a secret file by hand
(its first line says it was written by `post-bootstrap.sh`): every bootstrap rewrites it. To add a new one, see
[Development: secrets](development.md#secrets).

### Replace this Mac's token

Copy the new token, then:

```bash
printf 'add-generic-password -U -s dotfiles-op -a %s -w %s\n' "$USER" "$(pbpaste)" | security -i
pbcopy < /dev/null
```

Don't use `security add-generic-password … -w` with its prompt: it cuts the input at 128 characters, and the
token is much longer.

### Take access away from a Mac

Revoke its service account on 1Password.com.
