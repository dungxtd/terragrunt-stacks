# MiniStack — local LocalStack-compatible AWS emulator + k3s.
# docker-compose.yml lives under ministack/.

DC := docker compose -f $(MINISTACK_COMPOSE)

.PHONY: ms-up ms-down ms-restart ms-status ms-logs
ms-up: ## Start MiniStack (docker compose up)
	@$(DC) up -d --wait
	@echo "✓ MiniStack ready on $(MINISTACK_EP)"
ms-down: ## Stop MiniStack + remove volumes
	@$(DC) down -v
	@echo "✓ MiniStack stopped"
ms-restart: ## Restart MiniStack containers
	@$(DC) restart
	@$(DC) up -d --wait
ms-status: ; @$(DC) ps                ## docker compose ps
ms-logs:   ; @$(DC) logs -f ministack  ## tail MiniStack logs

.PHONY: ms-reset
ms-reset: ## Wipe MiniStack state via /_ministack/reset endpoint
	@curl -sf -X POST $(MINISTACK_EP)/_ministack/reset > /dev/null && echo "✓ MiniStack state cleared" || echo "✗ Reset failed"

.PHONY: ms-seed
ms-seed: ms-up ## Create S3 state bucket + DynamoDB lock table
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
ms-kubeconfig: ## Write k3s kubeconfig to .kubeconfig-ministack
	@docker exec $(MINISTACK_EKS_CONTAINER) cat /etc/rancher/k3s/k3s.yaml \
		| sed 's|127.0.0.1|localhost|g' > $(MINISTACK_KUBECONFIG)
	@echo "✓ Kubeconfig written to $(MINISTACK_KUBECONFIG)"

.PHONY: ms-test
ms-test: ms-up ## Sanity-check STS / S3 / EC2 against MiniStack
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) sts get-caller-identity && echo "✓ STS OK" || echo "✗ STS failed"
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) s3 ls > /dev/null 2>&1 && echo "✓ S3 OK" || echo "✗ S3 failed"
	@AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
		aws --endpoint-url $(MINISTACK_EP) ec2 describe-vpcs > /dev/null 2>&1 && echo "✓ EC2 OK" || echo "✗ EC2 failed"

.PHONY: ms-init
ms-init: ms-up ms-seed ## Bring up MiniStack + seed backends
	@echo "MiniStack ready. Next: make ms-bootstrap"

.PHONY: ms-bootstrap
ms-bootstrap: tg-clean ms-reset ms-seed ## Full local bootstrap: stack apply + GitOps
	@cd $(STACKS)/vault-consul/ministack && terragrunt stack generate && terragrunt stack run apply $(TG_FLAGS)
	@KUBECONFIG=$(MINISTACK_KUBECONFIG) kubectl apply -f $(GITOPS_DIR)/apps/root.yaml || true
	@KUBECONFIG=$(MINISTACK_KUBECONFIG) kubectl get applications -n argocd 2>/dev/null || true
	@lsof -ti :18200 | xargs kill 2>/dev/null || true
	@echo "✓ MiniStack bootstrapped"
	@echo "  KUBECONFIG: export KUBECONFIG=$(MINISTACK_KUBECONFIG)"
	@echo "  Vault:    make vault-status"
	@echo "  ArgoCD:   https://localhost:30443"

.PHONY: ms-teardown
ms-teardown: ms-down ## Tear down MiniStack
	@echo "✓ Local environment torn down"

.PHONY: gitops-bootstrap
gitops-bootstrap: ## Apply ArgoCD App-of-Apps root
	@kubectl apply -f $(GITOPS_DIR)/apps/root.yaml
	@echo "✓ ArgoCD root Application applied"
