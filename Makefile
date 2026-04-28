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

MINISTACK_IMAGE   := ministackorg/ministack:latest
MINISTACK_NAME    := ministack
MINISTACK_PORT    := 4566
MINISTACK_EP      := http://localhost:$(MINISTACK_PORT)
LOCAL_HCL         := local.hcl
STATE_BUCKET      := tf-state-$(APP)-us-east-1

.PHONY: ms-up
ms-up:
	@if docker ps --format '{{.Names}}' | grep -q '^$(MINISTACK_NAME)$$'; then \
		echo "✓ MiniStack is already running"; \
	else \
		echo "Starting MiniStack..."; \
		docker run -d --name $(MINISTACK_NAME) \
			-p $(MINISTACK_PORT):4566 \
			-v /var/run/docker.sock:/var/run/docker.sock \
			-u root \
			$(MINISTACK_IMAGE); \
		echo "Waiting for MiniStack to be ready..."; \
		for i in $$(seq 1 30); do \
			if curl -sf $(MINISTACK_EP)/_ministack/health > /dev/null 2>&1; then \
				echo "✓ MiniStack is ready"; \
				break; \
			fi; \
			sleep 1; \
		done; \
	fi

.PHONY: ms-down
ms-down:
	@docker rm -f $(MINISTACK_NAME) 2>/dev/null && echo "✓ MiniStack stopped" || echo "MiniStack is not running"

.PHONY: ms-restart
ms-restart: ms-down ms-up

.PHONY: ms-status
ms-status:
	@if docker ps --format '{{.Names}}' | grep -q '^$(MINISTACK_NAME)$$'; then \
		echo "✓ MiniStack is running on $(MINISTACK_EP)"; \
		echo "  Container: $$(docker ps --filter name=$(MINISTACK_NAME) --format '{{.Status}}')"; \
	else \
		echo "✗ MiniStack is not running"; \
	fi

.PHONY: ms-logs
ms-logs:
	@docker logs -f $(MINISTACK_NAME)

.PHONY: ms-reset
ms-reset:
	@echo "Resetting all MiniStack state..."
	@curl -sf -X POST $(MINISTACK_EP)/_ministack/reset > /dev/null && echo "✓ MiniStack state cleared" || echo "✗ Reset failed"

.PHONY: ms-enable
ms-enable: tg-clean
	@sed -i.bak 's/use_ministack = false/use_ministack = true/' $(LOCAL_HCL) && rm -f $(LOCAL_HCL).bak
	@echo "✓ MiniStack enabled in $(LOCAL_HCL)"

.PHONY: ms-disable
ms-disable: tg-clean
	@sed -i.bak 's/use_ministack = true/use_ministack = false/' $(LOCAL_HCL) && rm -f $(LOCAL_HCL).bak
	@echo "✓ MiniStack disabled in $(LOCAL_HCL)"

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
