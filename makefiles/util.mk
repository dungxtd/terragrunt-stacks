# Misc cleanup + formatting.

.PHONY: tg-clean
tg-clean: ## Wipe .terragrunt-cache, .terragrunt-stack, .terraform across units/stacks
	@find $(UNITS) $(STACKS) -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terragrunt-stack" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform"        -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(UNITS) $(STACKS) -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true
	@echo "✓ Cache cleared"

.PHONY: setup-terragrunt fmt fmt-check graph-vault
setup-terragrunt: ## Install Terragrunt $(TG_VERSION) — /usr/local/bin if writable, else ~/.local/bin
	@OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); \
	if [ -w /usr/local/bin ]; then DEST=/usr/local/bin; \
	else DEST=$$HOME/.local/bin; mkdir -p "$$DEST"; fi; \
	curl -sL "https://github.com/gruntwork-io/terragrunt/releases/download/v$(TG_VERSION)/terragrunt_$${OS}_$${ARCH}" \
		-o "$$DEST/terragrunt" && \
	chmod +x "$$DEST/terragrunt" && \
	"$$DEST/terragrunt" --version

fmt: ## terraform fmt + terragrunt hcl fmt (writes)
	terraform fmt -recursive $(UNITS)
	terragrunt hcl fmt

fmt-check: ## Verify HCL/TF formatting — exit 1 if any file needs changes (CI gate)
	@terragrunt hcl fmt --check || { echo "HCL needs formatting — run: make fmt"; exit 1; }
	@terraform fmt -recursive -check $(UNITS) || { echo "TF needs formatting — run: make fmt"; exit 1; }
	@echo "✓ formatting ok"

graph-vault: ## terragrunt graph-dependencies for vault-consul stack
	cd $(STACKS)/vault-consul/production && terragrunt graph-dependencies
