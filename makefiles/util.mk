# Misc cleanup + formatting.

.PHONY: tg-clean
tg-clean: ## Wipe .terragrunt-cache, .terragrunt-stack, .terraform across units/stacks
	@find $(UNITS) $(STACKS) -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terragrunt-stack" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform"        -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
	@echo "✓ Cache cleared"

.PHONY: fmt graph-vault
fmt: ## terraform fmt + terragrunt hcl fmt
	terraform fmt -recursive $(UNITS)
	terragrunt hcl fmt
graph-vault: ## terragrunt graph-dependencies for vault-consul stack
	cd $(STACKS)/vault-consul/production && terragrunt graph-dependencies
