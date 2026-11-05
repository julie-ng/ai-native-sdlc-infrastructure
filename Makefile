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

.PHONY: init-kv-secrets
init-kv-secrets:
	@bash scripts/init-kv-secrets.sh

.PHONY: reset-sdlc-secrets
reset-sdlc-secrets:
	@bash scripts/reset-sdlc-secrets.sh

# Chart 2.0.16 runs Argo v4.1.6, matching the local CLI.
ARGO_CHART_VERSION := 2.0.16
ARGO_VERSION := v4.1.6
# Must match argo_namespace in defaults.auto.tfvars; Terraform creates the namespace.
ARGO_NAMESPACE ?= argo
# Must match agents_namespace in defaults.auto.tfvars; Terraform creates the namespace.
AGENTS_NAMESPACE ?= agents

.PHONY: install-argo uninstall-argo
install-argo:
	kubectl apply --server-side -k "https://github.com/argoproj/argo-workflows/manifests/base/crds/full?ref=$(ARGO_VERSION)"
	helm upgrade --install argo-workflows argo-workflows \
		--repo https://argoproj.github.io/argo-helm \
		--version $(ARGO_CHART_VERSION) \
		--namespace $(ARGO_NAMESPACE) \
		--values helm/argo-workflows/values.yaml \
		--wait \
		--timeout 5m

# CRDs, workflow objects and Terraform-owned resources are retained.
uninstall-argo:
	helm uninstall argo-workflows --namespace $(ARGO_NAMESPACE) --wait

.PHONY: create-argo-executor-token
create-argo-executor-token:
	kubectl apply --namespace $(AGENTS_NAMESPACE) --filename manifests/argo-executor-token.yaml
