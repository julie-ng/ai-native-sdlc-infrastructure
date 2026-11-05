#!/usr/bin/env bash
set -euo pipefail

# Real values replace the initialization placeholders; the GitHub App key is untouched.
admin_token_secret='platform-services-admin-token'
hmac_key_secret='platform-services-hmac-key'
gpg_private_key_secret='agent-gpg-private-key'
gpg_public_key_secret='agent-gpg-public-key'
gpg_fingerprint_secret='agent-gpg-fingerprint'

# Make runs this script from the repository root.
source scripts/.env

# KV name from Terraform output
vault_name="$(terraform output -json summary | jq -r '.shared.key_vault.name')"

# 🧹 CLEAN UP SCRIPT
# Every GPG operation, including agent shutdown, uses this disposable home.
umask 077
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sdlc-secrets.XXXXXX")"
export GNUPGHOME="$temp_dir/gnupg"
cleanup() {
  gpgconf --homedir "$GNUPGHOME" --kill all >/dev/null 2>&1 || true
  rm -rf -- "$temp_dir"
}

# Run cleanup on completion or error; Ctrl+C and termination also exit through it,
# so temporary private keys and the disposable GPG agent are not left behind.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -m 700 "$GNUPGHOME"

# GPG - Generate Key
# No passphrase: the agent imports this key for unattended commit signing.
gpg \
  --homedir "$GNUPGHOME" \
  --batch \
  --pinentry-mode loopback \
  --passphrase '' \
  --quick-generate-key "$AGENT_GPG_USER_NAME <$AGENT_GPG_USER_EMAIL>" ed25519 sign 1y

# GPG - Get Fingerprint
fingerprint="$(
  gpg \
    --homedir "$GNUPGHOME" \
    --batch \
    --with-colons \
    --list-secret-keys |
    awk -F: '$1 == "fpr" { print $10; exit }'
)"

# GPG - Export Secret Key
gpg \
  --homedir "$GNUPGHOME" \
  --batch \
  --armor \
  --output "$temp_dir/$gpg_private_key_secret" \
  --export-secret-keys "$fingerprint"

# GPG - Export Public Key
gpg \
  --homedir "$GNUPGHOME" \
  --batch \
  --armor \
  --output "$temp_dir/$gpg_public_key_secret" \
  --export "$fingerprint"
printf '%s' "$fingerprint" > "$temp_dir/$gpg_fingerprint_secret"

# Keep token values out of process arguments and terminal output.
for secret_name in "$admin_token_secret" "$hmac_key_secret"; do
  openssl rand -base64 32 | tr -d '\n' > "$temp_dir/$secret_name"
done

# Generate everything before the first write. Azure updates are sequential, not atomic;
# an upload failure leaves earlier versions in place and stops the remaining uploads.
for secret_name in \
  "$admin_token_secret" \
  "$hmac_key_secret" \
  "$gpg_private_key_secret" \
  "$gpg_public_key_secret" \
  "$gpg_fingerprint_secret"; do
  az keyvault secret set \
    --vault-name "$vault_name" \
    --name "$secret_name" \
    --file "$temp_dir/$secret_name" \
    --encoding utf-8 \
    --output none \
    --only-show-errors
  printf 'Reset secret: %s\n' "$secret_name"
done
