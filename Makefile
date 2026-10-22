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

plan-kubernetes:
	terraform plan -target=module.kubernetes -out plan.tfplan

# Full plan - should show no changes once all five steps are applied
plan:
	terraform plan -out plan.tfplan

apply:
	terraform apply plan.tfplan

.PHONY: start-cluster stop-cluster
start-cluster stop-cluster:
	@set -eu; \
	cluster_summary="$$(terraform output -json summary)"; \
	cluster_rg="$$(printf '%s\n' "$$cluster_summary" | jq -er '.cluster.resource_group.name | select(type == "string" and length > 0)')"; \
	cluster_name="$$(printf '%s\n' "$$cluster_summary" | jq -er '.cluster.aks_cluster.name | select(type == "string" and length > 0)')"; \
	az aks $(patsubst %-cluster,%,$@) --resource-group "$$cluster_rg" --name "$$cluster_name"

kubecontext:
	az aks get-credentials \
		--resource-group $$(terraform output -json summary | jq -r .cluster.resource_group.name) \
		--name $$(terraform output -json summary | jq -r .cluster.aks_cluster.name)
	kubelogin convert-kubeconfig -l azurecli
	kubectl get nodes
