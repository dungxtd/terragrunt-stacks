SHELL := /bin/bash
HELM_CHART := helm/payments-app
STACKS_DIR := stacks
UNITS_DIR  := units

TG_FLAGS := --non-interactive --backend-bootstrap

# ── Stack Deploy ─────────────────────────────────────────────────
# Usage: make stack-sops <action>   (plan / apply / destroy)
#        make stack-vault <action>

.PHONY: stack-sops
stack-sops:
	$(eval ACTION := $(filter plan apply destroy,$(MAKECMDGOALS)))
	@if [ -z "$(ACTION)" ]; then echo "Usage: make stack-sops <plan|apply|destroy>"; exit 1; fi
	cd $(STACKS_DIR)/sops-linkerd && terragrunt stack generate && terragrunt stack run $(ACTION) $(TG_FLAGS)

.PHONY: stack-vault
stack-vault:
	$(eval ACTION := $(filter plan apply destroy,$(MAKECMDGOALS)))
	@if [ -z "$(ACTION)" ]; then echo "Usage: make stack-vault <plan|apply|destroy>"; exit 1; fi
	cd $(STACKS_DIR)/vault-consul && terragrunt stack generate && terragrunt stack run $(ACTION) $(TG_FLAGS)

# Catch plan/apply/destroy so Make doesn't treat them as missing targets
.PHONY: plan apply destroy
plan apply destroy:
	@true

# ── Individual Unit Apply ────────────────────────────────────────

.PHONY: apply-vpc
apply-vpc:
	cd $(UNITS_DIR)/vpc && terragrunt apply

.PHONY: apply-eks
apply-eks:
	cd $(UNITS_DIR)/eks && terragrunt apply

.PHONY: apply-kms
apply-kms:
	cd $(UNITS_DIR)/kms && terragrunt apply

.PHONY: apply-rds
apply-rds:
	cd $(UNITS_DIR)/rds && terragrunt apply

.PHONY: apply-vault
apply-vault:
	cd $(UNITS_DIR)/vault && terragrunt apply

.PHONY: apply-consul
apply-consul:
	cd $(UNITS_DIR)/consul && terragrunt apply

.PHONY: apply-argocd
apply-argocd:
	cd $(UNITS_DIR)/argocd && terragrunt apply

.PHONY: apply-linkerd
apply-linkerd:
	cd $(UNITS_DIR)/linkerd && terragrunt apply

.PHONY: apply-flagger
apply-flagger:
	cd $(UNITS_DIR)/flagger && terragrunt apply

# ── Helm (app deploy) ───────────────────────────────────────────

.PHONY: helm-sops
helm-sops:
	helm upgrade --install payments-app $(HELM_CHART) \
		-f $(HELM_CHART)/values/sops-linkerd.yaml \
		-n payments-app --create-namespace

.PHONY: helm-vault
helm-vault:
	helm upgrade --install payments-app $(HELM_CHART) \
		-f $(HELM_CHART)/values/vault-consul.yaml \
		-n payments-app --create-namespace

.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall payments-app -n payments-app

.PHONY: helm-template-sops
helm-template-sops:
	helm template payments-app $(HELM_CHART) -f $(HELM_CHART)/values/sops-linkerd.yaml

.PHONY: helm-template-vault
helm-template-vault:
	helm template payments-app $(HELM_CHART) -f $(HELM_CHART)/values/vault-consul.yaml

# ── Kubeconfig + Env ─────────────────────────────────────────────

.PHONY: kubeconfig
kubeconfig:
	aws eks --region $$(cd $(UNITS_DIR)/vpc && terragrunt output -raw region) \
		update-kubeconfig \
		--name $$(cd $(UNITS_DIR)/eks && terragrunt output -raw cluster_name)

.PHONY: set-env
set-env:
	@echo "Run: source set_env.sh"

# ── Vault Operations (vault-consul env) ─────────────────────────

.PHONY: vault-status
vault-status:
	vault status

.PHONY: vault-db-creds
vault-db-creds:
	vault read payments-app/database/creds/payments

.PHONY: vault-pki-roots
vault-pki-roots:
	vault read consul/server/pki/cert/ca_chain

.PHONY: vault-lease-clean
vault-lease-clean:
	vault lease revoke --force --prefix payments-app/database

# ── Consul Operations (vault-consul env) ────────────────────────

.PHONY: consul-members
consul-members:
	consul members

.PHONY: consul-intentions
consul-intentions:
	consul intention list

.PHONY: consul-ca-roots
consul-ca-roots:
	curl -sk -H "X-Consul-Token:$${CONSUL_HTTP_TOKEN}" \
		$${CONSUL_HTTP_ADDR}/v1/connect/ca/roots | jq .

# ── ArgoCD ───────────────────────────────────────────────────────

.PHONY: argocd-password
argocd-password:
	@kubectl get secrets -n argocd argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

.PHONY: argocd-sync
argocd-sync:
	argocd app sync payments-app

.PHONY: argocd-apps
argocd-apps:
	argocd app list

# ── Test / Verify ────────────────────────────────────────────────

.PHONY: test-app
test-app:
	@echo "Testing payments-app endpoint..."
	curl -sk $$(kubectl get svc -n payments-app payments-app \
		-o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081/payments

.PHONY: test-db
test-db:
	@echo "Testing PostgreSQL connection..."
	pg_isready -h $$(cd $(UNITS_DIR)/rds && terragrunt output -raw rds_endpoint) -p 5432

.PHONY: test-mesh
test-mesh:
	@echo "Checking mTLS proxy status..."
	kubectl exec -n payments-app deploy/payments-app -c linkerd-proxy -- \
		/usr/lib/linkerd/linkerd-identity-end-entity 2>/dev/null || \
	kubectl exec -n payments-app deploy/payments-app -c envoy-sidecar -- \
		curl -s localhost:19000/certs 2>/dev/null || \
	echo "No mesh sidecar found"

# ── Cleanup ──────────────────────────────────────────────────────

.PHONY: clean-app
clean-app:
	kubectl patch app payments-app -n argocd \
		-p '{"metadata": {"finalizers": ["resources-finalizer.argocd.argoproj.io"]}}' --type merge
	kubectl delete app payments-app -n argocd

.PHONY: clean-helm
clean-helm:
	helm uninstall payments-app -n payments-app || true

.PHONY: clean-all
clean-all: clean-helm
	cd $(STACKS_DIR)/sops-linkerd && terragrunt stack run destroy $(TG_FLAGS) || true
	cd $(STACKS_DIR)/vault-consul && terragrunt stack run destroy $(TG_FLAGS) || true

# ── Utility ──────────────────────────────────────────────────────

.PHONY: fmt
fmt:
	terraform fmt -recursive $(UNITS_DIR)

.PHONY: graph
graph:
	cd $(STACKS_DIR)/vault-consul && terragrunt graph-dependencies

.PHONY: graph-sops
graph-sops:
	cd $(STACKS_DIR)/sops-linkerd && terragrunt graph-dependencies
