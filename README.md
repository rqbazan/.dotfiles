# dotfiles

My Mac, declared. One command sets up a new machine and brings an existing one up to date.

## Set up a Mac

1. Sign in with your Apple Account during macOS setup, then open the App Store and check you're signed in
   there too: the App Store apps and Ardia's sync need it.
2. Run:

   ```bash
   curl -fsSL https://rcrd.space/mac/install.sh | bash
   ```

3. When it asks for the 1Password token, copy it on your phone (the item for `dotfiles-personal` or
   `dotfiles-work`, in `Private`) and paste it on the Mac. It's what lets this Mac read its secrets, like its
   SSH key. Not at hand? Press Enter: the rest installs, and the next run asks again.
4. Do the few steps no script can: [runbook](docs/runbook.md).

Running the same command again is how a Mac stays up to date.

## Built on

| Tool | What it does here |
| --- | --- |
| [mise](https://mise.jdx.dev) | installs every tool at a pinned version |
| [`mise bootstrap`](https://mise.jdx.dev/bootstrap.html) | applies [`config/mise`](config/mise): apps, macOS settings, config files symlinked into `~` |
| [Homebrew](https://brew.sh) | the apps (casks), installed through `mise bootstrap` |
| [1Password service accounts](https://developer.1password.com/docs/service-accounts) | the secrets, filled into the templates in [`config/secrets`](config/secrets) |
| [Tart](https://tart.run) + [bats](https://bats-core.readthedocs.io) | the tests, on a throwaway macOS VM |

## Docs

- [Runbook](docs/runbook.md): what you do by hand, before and after the command.
- [Development](docs/development.md): how the repo works, how to change it, how to test it.
