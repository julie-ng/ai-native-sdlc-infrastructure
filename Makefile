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

# Full plan - should show no changes once all five steps are applied
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

.PHONY: start-cluster stop-cluster start-database stop-database start-platform stop-platform kubecontext
start-cluster stop-cluster:
	az aks $(patsubst %-cluster,%,$@) --resource-group "$(AKS_RESOURCE_GROUP)" --name "$(AKS_CLUSTER_NAME)"

start-database stop-database:
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
