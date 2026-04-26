SHELL    := /bin/bash
APP      := payments-app
CHART    := helm/$(APP)
STACKS   := stacks
UNITS    := units
TG_FLAGS := --non-interactive --backend-bootstrap

# ── Stack ───────────────────────────────────────────────────────
# Usage: make stack-<name> <plan|apply|destroy>

STACKS_MAP := sops:sops-linkerd vault:vault-consul

define stack-rule
.PHONY: stack-$(1)
stack-$(1):
	$$(eval ACTION := $$(filter plan apply destroy,$$(MAKECMDGOALS)))
	@if [ -z "$$(ACTION)" ]; then echo "Usage: make stack-$(1) <plan|apply|destroy>"; exit 1; fi
	cd $(STACKS)/$2 && terragrunt stack generate && terragrunt stack run $$(ACTION) $(TG_FLAGS)
endef
$(foreach s,$(STACKS_MAP),$(eval $(call stack-rule,$(word 1,$(subst :, ,$s)),$(word 2,$(subst :, ,$s)))))

.PHONY: plan apply destroy
plan apply destroy: ;@:

# ── Unit ────────────────────────────────────────────────────────
# Usage: make <apply|destroy|plan>-<unit>

UNIT_LIST := vpc eks kms rds vault consul argocd linkerd flagger datadog aws-alb sops-secrets

define unit-rule
.PHONY: apply-$(1) destroy-$(1) plan-$(1)
apply-$(1)  : ; cd $(UNITS)/$(1) && terragrunt apply
destroy-$(1): ; cd $(UNITS)/$(1) && terragrunt destroy
plan-$(1)   : ; cd $(UNITS)/$(1) && terragrunt plan
endef
$(foreach u,$(UNIT_LIST),$(eval $(call unit-rule,$u)))

# ── Helm ────────────────────────────────────────────────────────
# Usage: make helm <sops|vault>         — install/upgrade
#        make helm-template <sops|vault> — dry-run render
#        make helm-uninstall             — remove release

HELM_VALUES := sops:sops-linkerd vault:vault-consul

.PHONY: helm
helm:
	$(eval ENV := $(filter sops vault,$(MAKECMDGOALS)))
	@if [ -z "$(ENV)" ]; then echo "Usage: make helm <sops|vault>"; exit 1; fi
	$(eval VFILE := $(word 2,$(subst :, ,$(filter $(ENV):%,$(HELM_VALUES)))))
	helm upgrade --install $(APP) $(CHART) -f $(CHART)/values/$(VFILE).yaml -n $(APP) --create-namespace

.PHONY: helm-template
helm-template:
	$(eval ENV := $(filter sops vault,$(MAKECMDGOALS)))
	@if [ -z "$(ENV)" ]; then echo "Usage: make helm-template <sops|vault>"; exit 1; fi
	$(eval VFILE := $(word 2,$(subst :, ,$(filter $(ENV):%,$(HELM_VALUES)))))
	helm template $(APP) $(CHART) -f $(CHART)/values/$(VFILE).yaml

.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall $(APP) -n $(APP)

.PHONY: sops vault
sops vault: ;@:

# ── Kubernetes ──────────────────────────────────────────────────

.PHONY: kubeconfig
kubeconfig:
	aws eks --region $$(cd $(UNITS)/vpc && terragrunt output -raw region) \
		update-kubeconfig --name $$(cd $(UNITS)/eks && terragrunt output -raw cluster_name)

.PHONY: argocd-password argocd-sync argocd-apps
argocd-password:
	@kubectl get secrets -n argocd argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo
argocd-sync: ; argocd app sync $(APP)
argocd-apps: ; argocd app list

# ── Vault / Consul ──────────────────────────────────────────────

.PHONY: vault-status vault-db-creds vault-pki-roots vault-lease-clean
vault-status:     ; vault status
vault-db-creds:   ; vault read $(APP)/database/creds/payments
vault-pki-roots:  ; vault read consul/server/pki/cert/ca_chain
vault-lease-clean:; vault lease revoke --force --prefix $(APP)/database

.PHONY: consul-members consul-intentions consul-ca-roots
consul-members:   ; consul members
consul-intentions:; consul intention list
consul-ca-roots:
	curl -sk -H "X-Consul-Token:$${CONSUL_HTTP_TOKEN}" \
		$${CONSUL_HTTP_ADDR}/v1/connect/ca/roots | jq .

# ── Test ────────────────────────────────────────────────────────

.PHONY: test-app test-db test-mesh
test-app:
	curl -sk $$(kubectl get svc -n $(APP) $(APP) \
		-o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081/payments
test-db:
	pg_isready -h $$(cd $(UNITS)/rds && terragrunt output -raw rds_endpoint) -p 5432
test-mesh:
	kubectl exec -n $(APP) deploy/$(APP) -c linkerd-proxy -- \
		/usr/lib/linkerd/linkerd-identity-end-entity 2>/dev/null || \
	kubectl exec -n $(APP) deploy/$(APP) -c envoy-sidecar -- \
		curl -s localhost:19000/certs 2>/dev/null || \
	echo "No mesh sidecar found"

# ── Cleanup ─────────────────────────────────────────────────────

.PHONY: clean-app clean-helm clean-all
clean-app:
	kubectl patch app $(APP) -n argocd \
		-p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge
	kubectl delete app $(APP) -n argocd
clean-helm: ; helm uninstall $(APP) -n $(APP) || true
clean-all: clean-helm
	cd $(STACKS)/sops-linkerd  && terragrunt stack run destroy $(TG_FLAGS) || true
	cd $(STACKS)/vault-consul && terragrunt stack run destroy $(TG_FLAGS) || true

# ── Utility ─────────────────────────────────────────────────────

.PHONY: fmt graph-sops graph-vault
fmt:        ; terraform fmt -recursive $(UNITS)
graph-sops: ; cd $(STACKS)/sops-linkerd  && terragrunt graph-dependencies
graph-vault:; cd $(STACKS)/vault-consul && terragrunt graph-dependencies
