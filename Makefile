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
		aws --endpoint-url $(MINISTACK_EP) dynamodb create-table \
			--table-name tf-state-lock \
			--attribute-definitions AttributeName=LockID,AttributeType=S \
			--key-schema AttributeName=LockID,KeyType=HASH \
			--billing-mode PAY_PER_REQUEST 2>/dev/null || true
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
	@echo "══════════════════════════════════════════════"
	@echo "  MiniStack local environment is ready!"
	@echo "  Run: make plan-vpc   or   make stack-sops plan"
	@echo "══════════════════════════════════════════════"

.PHONY: ms-teardown
ms-teardown: ms-disable ms-down
	@echo "✓ Local environment torn down"

# ── Utility ─────────────────────────────────────────────────

.PHONY: tg-clean
tg-clean:
	@echo "Clearing terragrunt cache..."
	@find $(UNITS) $(STACKS) -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terragrunt-stack" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
	@echo "✓ Cache cleared"

.PHONY: fmt graph-sops graph-vault
fmt:        ; terraform fmt -recursive $(UNITS)
graph-sops: ; cd $(STACKS)/sops-linkerd  && terragrunt graph-dependencies
graph-vault:; cd $(STACKS)/vault-consul && terragrunt graph-dependencies
