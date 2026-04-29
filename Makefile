SHELL    := /bin/bash
APP      := payments-app
CHART    := gitops/charts/$(APP)
STACKS   := stacks
UNITS    := units
TG_FLAGS := --non-interactive --backend-bootstrap

# ── Stack ───────────────────────────────────────────────────────
# Usage: make stack-<name> <plan|apply|destroy>

STACKS_MAP := vault:vault-consul

define stack-rule
.PHONY: stack-$(1)
stack-$(1):
	$$(eval ACTION := $$(filter plan apply destroy,$$(MAKECMDGOALS)))
	@if [ -z "$$(ACTION)" ]; then echo "Usage: make stack-$(1) <plan|apply|destroy>"; exit 1; fi
	cd $(STACKS)/$2 && terragrunt stack generate && terragrunt stack run $$(ACTION) $(TG_FLAGS)
	@if [ "$$(ACTION)" = "apply" ] && [ -f .kubeconfig-ministack ]; then \
		echo ""; \
		echo "  KUBECONFIG: export KUBECONFIG=$$(pwd)/.kubeconfig-ministack"; \
	fi
endef
$(foreach s,$(STACKS_MAP),$(eval $(call stack-rule,$(word 1,$(subst :, ,$s)),$(word 2,$(subst :, ,$s)))))

.PHONY: plan apply destroy
plan apply destroy: ;@:

# ── Unit ────────────────────────────────────────────────────────
# Usage: make <apply|destroy|plan>-<unit>

UNIT_LIST := vpc eks kms rds vault vault-config certs consul argocd linkerd flagger datadog aws-alb github-runner

define unit-rule
.PHONY: apply-$(1) destroy-$(1) plan-$(1)
apply-$(1)  : ; cd $(UNITS)/$(1) && terragrunt apply
destroy-$(1): ; cd $(UNITS)/$(1) && terragrunt destroy
plan-$(1)   : ; cd $(UNITS)/$(1) && terragrunt plan
endef
$(foreach u,$(UNIT_LIST),$(eval $(call unit-rule,$u)))

# ── Helm ────────────────────────────────────────────────────────
# Usage: make helm <vault>         — install/upgrade
#        make helm-template <vault> — dry-run render
#        make helm-uninstall        — remove release

HELM_VALUES := vault:vault-consul

.PHONY: helm
helm:
	$(eval ENV := $(filter vault,$(MAKECMDGOALS)))
	@if [ -z "$(ENV)" ]; then echo "Usage: make helm <vault>"; exit 1; fi
	$(eval VFILE := $(word 2,$(subst :, ,$(filter $(ENV):%,$(HELM_VALUES)))))
	helm upgrade --install $(APP) $(CHART) -f $(CHART)/values/$(VFILE).yaml -n $(APP) --create-namespace

.PHONY: helm-template
helm-template:
	$(eval ENV := $(filter vault,$(MAKECMDGOALS)))
	@if [ -z "$(ENV)" ]; then echo "Usage: make helm-template <vault>"; exit 1; fi
	$(eval VFILE := $(word 2,$(subst :, ,$(filter $(ENV):%,$(HELM_VALUES)))))
	helm template $(APP) $(CHART) -f $(CHART)/values/$(VFILE).yaml

.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall $(APP) -n $(APP)

.PHONY: vault
vault: ;@:

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

VAULT_PF_PORT := 18200
VAULT_CURL    := curl -sf -H "X-Vault-Token: root" http://localhost:$(VAULT_PF_PORT)

define vault-pf
	@KUBECONFIG=$(MINISTACK_KUBECONFIG) kubectl port-forward svc/vault $(VAULT_PF_PORT):8200 -n vault >/dev/null 2>&1 & sleep 2
endef
define vault-pf-stop
	@lsof -ti :$(VAULT_PF_PORT) | xargs kill 2>/dev/null || true
endef

.PHONY: vault-status vault-db-creds vault-pki-roots vault-lease-clean
vault-status:
	$(call vault-pf)
	@$(VAULT_CURL)/v1/sys/health | python3 -m json.tool
	$(call vault-pf-stop)

vault-db-creds:
	$(call vault-pf)
	@$(VAULT_CURL)/v1/$(APP)/database/creds/payments | python3 -m json.tool
	$(call vault-pf-stop)

vault-pki-roots:
	$(call vault-pf)
	@$(VAULT_CURL)/v1/consul/server/pki/cert/ca_chain | python3 -m json.tool
	$(call vault-pf-stop)

vault-lease-clean:
	$(call vault-pf)
	@$(VAULT_CURL)/v1/sys/leases/revoke-force/$(APP)/database -X PUT
	@echo "✓ Leases revoked"
	$(call vault-pf-stop)

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
	cd $(STACKS)/vault-consul && terragrunt stack run destroy $(TG_FLAGS) || true

# ── MiniStack ──────────────────────────────────────────────

MINISTACK_NAME          := ministack
MINISTACK_PORT          := 4566
MINISTACK_EP            := http://localhost:$(MINISTACK_PORT)
LOCAL_HCL               := local.hcl
STATE_BUCKET            := tf-state-$(APP)-us-east-1
MINISTACK_EKS_CONTAINER := ministack-eks-terragrunt-infra-eks
MINISTACK_KUBECONFIG    := .kubeconfig-ministack

.PHONY: ms-up
ms-up:
	@docker compose up -d --wait
	@echo "✓ MiniStack is ready on $(MINISTACK_EP)"

.PHONY: ms-down
ms-down:
	@docker compose down -v
	@echo "✓ MiniStack stopped"

.PHONY: ms-restart
ms-restart:
	@docker compose restart
	@docker compose up -d --wait

.PHONY: ms-status
ms-status:
	@docker compose ps

.PHONY: ms-logs
ms-logs:
	@docker compose logs -f ministack

.PHONY: ms-reset
ms-reset:
	@echo "Resetting all MiniStack state..."
	@curl -sf -X POST $(MINISTACK_EP)/_ministack/reset > /dev/null && echo "✓ MiniStack state cleared" || echo "✗ Reset failed"

.PHONY: ms-enable
ms-enable: tg-clean
	@sed -i.bak 's/active_env = "aws"/active_env = "ministack"/' $(LOCAL_HCL) && rm -f $(LOCAL_HCL).bak
	@echo "✓ Switched to ministack env in $(LOCAL_HCL)"

.PHONY: ms-disable
ms-disable: tg-clean
	@sed -i.bak 's/active_env = "ministack"/active_env = "aws"/' $(LOCAL_HCL) && rm -f $(LOCAL_HCL).bak
	@echo "✓ Switched to aws env in $(LOCAL_HCL)"

.PHONY: ms-seed
ms-seed: ms-up
	@echo "Creating S3 state bucket and DynamoDB lock table..."
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) s3 mb s3://tf-state-terragrunt-infra-ap-southeast-1 2>/dev/null || true
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --no-cli-pager --endpoint-url $(MINISTACK_EP) dynamodb create-table \
			--table-name tf-state-lock \
			--attribute-definitions AttributeName=LockID,AttributeType=S \
			--key-schema AttributeName=LockID,KeyType=HASH \
			--billing-mode PAY_PER_REQUEST >/dev/null 2>&1 || true
	@echo "✓ State backend ready"

.PHONY: ms-kubeconfig
ms-kubeconfig:
	@docker exec $(MINISTACK_EKS_CONTAINER) cat /etc/rancher/k3s/k3s.yaml \
		| sed 's|127.0.0.1|localhost|g' > $(MINISTACK_KUBECONFIG)
	@echo "✓ Kubeconfig written to $(MINISTACK_KUBECONFIG)"

.PHONY: ms-test
ms-test: ms-up
	@echo "Testing MiniStack connectivity..."
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) sts get-caller-identity && echo "✓ STS OK" || echo "✗ STS failed"
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) s3 ls > /dev/null 2>&1 && echo "✓ S3 OK" || echo "✗ S3 failed"
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) ec2 describe-vpcs > /dev/null 2>&1 && echo "✓ EC2 OK" || echo "✗ EC2 failed"

.PHONY: ms-init
ms-init: ms-up ms-enable ms-seed
	@echo ""
	@echo "══════════════════════════════════════════════════"
	@echo "  MiniStack local environment is ready!"
	@echo "  Run: make ms-bootstrap  (full auto)"
	@echo "  Or:  make stack-vault apply"
	@echo "  Then: make gitops-bootstrap"
	@echo "══════════════════════════════════════════════════"

.PHONY: ms-bootstrap
ms-bootstrap: tg-clean ms-reset ms-seed
	@echo ""
	@echo "═══ Deploying infrastructure stack… ═══"
	@cd $(STACKS)/vault-consul && terragrunt stack generate && terragrunt stack run apply $(TG_FLAGS)
	@echo ""
	@echo "═══ Bootstrapping GitOps… ═══"
	@KUBECONFIG=$(shell pwd)/.kubeconfig-ministack kubectl apply -f $(GITOPS_DIR)/appset.yaml 2>/dev/null || true
	@lsof -ti :18200 | xargs kill 2>/dev/null || true
	@echo ""
	@echo "══════════════════════════════════════════════════"
	@echo "  ✓ MiniStack fully bootstrapped!"
	@echo ""
	@echo "  KUBECONFIG: export KUBECONFIG=$(shell pwd)/.kubeconfig-ministack"
	@echo ""
	@echo "  Vault:    make vault-status"
	@echo "  ArgoCD:   https://localhost:30443"
	@echo "  DB creds: make vault-db-creds"
	@echo "══════════════════════════════════════════════════"

.PHONY: ms-teardown
ms-teardown: ms-disable ms-down
	@echo "✓ Local environment torn down"

GITOPS_DIR          := gitops
MINISTACK_KUBECONFIG := $(shell pwd)/.kubeconfig-ministack

.PHONY: gitops-bootstrap
gitops-bootstrap:
	@echo "Bootstrapping ArgoCD ApplicationSet..."
	@kubectl apply -f $(GITOPS_DIR)/appset.yaml
	@echo "✓ ArgoCD ApplicationSet applied — ArgoCD will sync apps"

.PHONY: vault-rotate-db
vault-rotate-db:
	$(call vault-pf)
	@$(VAULT_CURL)/v1/$(APP)/database/rotate-root/payments -X PUT
	@echo "✓ DB root credentials rotated"
	$(call vault-pf-stop)

# ── Utility ─────────────────────────────────────────────────

.PHONY: tg-clean
tg-clean:
	@echo "Clearing terragrunt cache..."
	@find $(UNITS) $(STACKS) -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terragrunt-stack" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
	@echo "✓ Cache cleared"

.PHONY: fmt graph-vault
fmt:        ; terraform fmt -recursive $(UNITS)
graph-vault:; cd $(STACKS)/vault-consul && terragrunt graph-dependencies
