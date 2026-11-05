#!/usr/bin/env bash
set -eu

# Bootstrap configuration: edit names here; replace real values in Azure Portal.
secret_names=(
  platform-services-admin-token
  platform-services-hmac-key
  gh-token-broker-app-private-key
  agent-gpg-private-key
)
bootstrap_value='BOOTSTRAP-REPLACE-ME'

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
