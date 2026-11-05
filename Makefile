# ========== #
#  Workflow  #
# ========== #
# Apply one module at a time, in order. Review each plan before applying.
# -target pulls in dependencies, e.g. plan-shared also plans networking.

init:
	terraform init

lint:
	terraform fmt -recursive -check
	terraform validate
	tflint --init
	tflint --recursive

plan-networking:
	terraform plan -target=module.networking -out plan.tfplan

plan-shared:
	terraform plan -target=module.shared -out plan.tfplan

plan-identities:
	terraform plan -target=module.identities -out plan.tfplan

plan-cluster:
	terraform plan -target=module.cluster -out plan.tfplan

plan-k8s:
	terraform plan -target=module.kubernetes -out plan.tfplan

plan-platform-stop:
	terraform plan -target=module.platform_stop_mi -out plan.tfplan

# Full plan - should show no changes once all stages are applied
plan:
	terraform plan -out plan.tfplan

apply:
	terraform apply plan.tfplan

# A combined summary can remain unavailable until the later Kubernetes stage is applied.
define cluster_target
set -eu; \
cluster_output="$$(terraform output -json cluster)"; \
cluster_rg="$$(printf '%s\n' "$$cluster_output" | jq -er '.resource_group.name | select(type == "string" and length > 0)')"; \
cluster_name="$$(printf '%s\n' "$$cluster_output" | jq -er '.aks_cluster.name | select(type == "string" and length > 0)')"
endef

# Defaults come from the local `platform_stop` Terraform output (identifiers only). Override with
# env vars or Make variables. Empty values must fail here: az turns an empty resource group into a
# malformed ARM URL and reports a misleading "invalid api-version" error.
tf_platform = $(shell terraform output -json platform_stop 2>/dev/null | jq -r '.$(1) // empty' 2>/dev/null)
AKS_RESOURCE_GROUP      ?= $(call tf_platform,AKS_RESOURCE_GROUP)
AKS_CLUSTER_NAME        ?= $(call tf_platform,AKS_CLUSTER_NAME)
POSTGRES_RESOURCE_GROUP ?= $(call tf_platform,AZ_POSTGRES_RESOURCE_GROUP)
POSTGRES_SERVER_NAME    ?= $(call tf_platform,AZ_POSTGRES_SERVER_NAME)

# Usage: $(call require,NAME,VALUE)
require = @[ -n "$(2)" ] || { echo "error: $(1) is empty; apply the platform_stop module or set it" >&2; exit 1; }

.PHONY: start-cluster stop-cluster start-database stop-database start-platform stop-platform kubecontext
start-cluster stop-cluster:
	$(call require,AKS_RESOURCE_GROUP,$(AKS_RESOURCE_GROUP))
	$(call require,AKS_CLUSTER_NAME,$(AKS_CLUSTER_NAME))
	az aks $(patsubst %-cluster,%,$@) --resource-group "$(AKS_RESOURCE_GROUP)" --name "$(AKS_CLUSTER_NAME)"

start-database stop-database:
	$(call require,POSTGRES_RESOURCE_GROUP,$(POSTGRES_RESOURCE_GROUP))
	$(call require,POSTGRES_SERVER_NAME,$(POSTGRES_SERVER_NAME))
	az postgres flexible-server $(patsubst %-database,%,$@) --resource-group "$(POSTGRES_RESOURCE_GROUP)" --name "$(POSTGRES_SERVER_NAME)"

start-platform:
	$(MAKE) start-database
	$(MAKE) start-cluster

stop-platform:
	$(MAKE) stop-cluster
	$(MAKE) stop-database

kubecontext:
	@$(cluster_target); \
	az aks get-credentials --resource-group "$$cluster_rg" --name "$$cluster_name"
	kubelogin convert-kubeconfig -l azurecli
	kubectl get nodes

# Creates a client secret for the local-dev service principal (never stored in Terraform).
# Printed once to the terminal: copy it into a git-ignored file or a password manager.
# --append keeps any existing credentials instead of replacing them.
.PHONY: local-dev-credential
local-dev-credential:
	@set -eu; \
	client_id="$$(terraform output -json local_dev | jq -er '.client_id')"; \
	az ad app credential reset --id "$$client_id" --append --years 1 --display-name local-dev

# Only metadata is listed; existing values are neither read nor replaced.
.PHONY: seed-key-vault-secrets
seed-key-vault-secrets:
	@set -eu; \
	vault_name="$${KEY_VAULT_NAME:-}"; \
	if [ -z "$$vault_name" ]; then \
		vault_name="$$(terraform output -json summary | jq -er '.shared.key_vault.name | select(type == "string" and length > 0)')"; \
	fi; \
	existing="$$(az keyvault secret list --vault-name "$$vault_name" --query '[].name' --output tsv --only-show-errors)"; \
	for secret_name in platform-services-admin-token platform-services-hmac-key gh-token-broker-app-private-key agent-gpg-private-key; do \
		if printf '%s\n' "$$existing" | grep -Fx -- "$$secret_name" >/dev/null; then \
			printf 'Skipping existing secret: %s\n' "$$secret_name"; \
		else \
			az keyvault secret set --vault-name "$$vault_name" --name "$$secret_name" --value 'BOOTSTRAP-REPLACE-ME' --output none --only-show-errors; \
			printf 'Created bootstrap secret: %s\n' "$$secret_name"; \
		fi; \
	done
