#!/usr/bin/env bash
set -eu

# Bootstrap configuration: edit names here; replace real values in Azure Portal.
secret_names=(
  platform-services-admin-token    # random value now
  platform-services-hmac-key       # random value now
  token-broker-gh-app-private-key  # placeholder, tagged
  agent-gpg-private-key            # placeholder, tagged → GPG script
  agent-gpg-public-key             # placeholder, tagged → GPG script
  agent-gpg-fingerprint            # placeholder, tagged → GPG script
)

bootstrap_value='INIT-ONLY-CHANGE-ME'

vault_name="${KEY_VAULT_NAME:-}"
if [ -z "$vault_name" ]; then
  vault_name="$(terraform output -json summary | jq -er '.shared.key_vault.name | select(type == "string" and length > 0)')"
fi

# Only metadata is listed; existing values are neither read nor replaced.
existing="$(az keyvault secret list \
  --vault-name "$vault_name" \
  --query '[].name' \
  --output tsv \
  --only-show-errors)"

for secret_name in "${secret_names[@]}"; do
  if printf '%s\n' "$existing" | grep -Fx -- "$secret_name" >/dev/null; then
    printf 'Skipping existing secret: %s\n' "$secret_name"
  else
    az keyvault secret set \
      --vault-name "$vault_name" \
      --name "$secret_name" \
      --value "$bootstrap_value" \
      --output none \
      --only-show-errors
    printf 'Created bootstrap secret: %s\n' "$secret_name"
  fi
done
