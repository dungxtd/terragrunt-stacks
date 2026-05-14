# Destroy lifecycle targets for production stack.
# predestroy-production → stack destroy → postdestroy-production (always)
#
# Env vars (all have defaults, CI overrides via workflow env:):
#   AWS_REGION, CLUSTER_NAME, PROJECT_TAG, STATE_BUCKET, STATE_PREFIX

CLUSTER_NAME  ?= terragrunt-infra-eks
PROJECT_TAG   ?= terragrunt-infra
STATE_BUCKET  ?= tf-state-terragrunt-stacks
STATE_PREFIX  ?= stacks/vault-consul/production
VAULT_PF_PORT ?= 18200

.PHONY: predestroy-production postdestroy-production \
        vault-pf-start vault-pf-stop \
        argocd-teardown drain-k8s wait-aws-reconcile force-unlock

predestroy-production: vault-pf-start argocd-teardown drain-k8s wait-aws-reconcile ## Pre-destroy: vault port-forward + ArgoCD teardown + drain k8s + wait AWS

postdestroy-production: vault-pf-stop ## Post-destroy cleanup — always run (stop vault port-forward)

vault-pf-start: ## Start Vault port-forward, verify Vault health (idempotent)
	$(SCRIPTS_DIR)/vault-portforward.sh start $(VAULT_PF_PORT)

vault-pf-stop: ## Stop Vault port-forward started by vault-pf-start
	$(SCRIPTS_DIR)/vault-portforward.sh stop $(VAULT_PF_PORT)

argocd-teardown: ## Cascade-delete ArgoCD ApplicationSets + Applications
	$(SCRIPTS_DIR)/argocd-teardown.sh

drain-k8s: ## Drain residual k8s resources not owned by Terragrunt
	$(SCRIPTS_DIR)/drain-k8s.sh

wait-aws-reconcile: ## Wait for ALB and EBS volumes to be cleaned up by AWS controllers
	AWS_REGION=$(AWS_REGION) CLUSTER_NAME=$(CLUSTER_NAME) PROJECT_TAG=$(PROJECT_TAG) \
		$(SCRIPTS_DIR)/wait-aws-reconcile.sh

force-unlock: ## Force-unlock stale Terragrunt state locks in DynamoDB
	STATE_BUCKET=$(STATE_BUCKET) STATE_PREFIX=$(STATE_PREFIX) \
		$(SCRIPTS_DIR)/force-unlock.sh
