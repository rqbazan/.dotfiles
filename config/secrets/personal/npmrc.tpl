; ~/.npmrc, written by scripts/post-bootstrap.sh from config/secrets and 1Password: change those, not this file.
; npm reads its token here, not from the environment: publishing a package before it has OIDC trusted publishing
//registry.npmjs.org/:_authToken={{ op://$DOTFILES_OP_PROFILE_VAULT/npm/credential }}
