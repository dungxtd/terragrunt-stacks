# Vault HTTP API helpers via local port-forward.
# Reuses :8200 if already forwarded (e.g. by `make pf-vault`); otherwise spins up
# a temporary port-forward on :18200 and tears it down.

VAULT_PF_PORT := 18200
# VAULT_TOKEN comes from `source scripts/load_env.sh`; fall back to "root" for dev.
VAULT_TOKEN_VAL := $$(if [ -n "$$VAULT_TOKEN" ]; then echo "$$VAULT_TOKEN"; else echo root; fi)
VAULT_CURL_BASE := curl -sf -H "X-Vault-Token: $$($(MAKE) -s _vault-token)"

# pick an existing port-forward on :8200 if running, else use ephemeral :18200
define vault-pf
	@if lsof -i :8200 >/dev/null 2>&1; then \
		echo "VAULT_PORT=8200" > /tmp/.vault-mk-port; \
	else \
		KUBECONFIG=$(or $(KUBECONFIG),$$HOME/.kube/config) kubectl port-forward svc/vault $(VAULT_PF_PORT):8200 -n vault >/dev/null 2>&1 & \
		sleep 2; \
		echo "VAULT_PORT=$(VAULT_PF_PORT)" > /tmp/.vault-mk-port; \
		echo "VAULT_PF_OWNED=1" >> /tmp/.vault-mk-port; \
	fi
endef
define vault-pf-stop
	@if [ -f /tmp/.vault-mk-port ] && grep -q VAULT_PF_OWNED=1 /tmp/.vault-mk-port; then \
		lsof -ti :$(VAULT_PF_PORT) | xargs kill 2>/dev/null || true; \
	fi
	@rm -f /tmp/.vault-mk-port
endef

VAULT_API := http://localhost:$$(grep VAULT_PORT /tmp/.vault-mk-port | cut -d= -f2)
VAULT_TOKEN_HDR := -H "X-Vault-Token: $${VAULT_TOKEN:-$${VAULT_DEFAULT_TOKEN:-root}}"

.PHONY: vault-status vault-db-creds vault-pki-roots vault-lease-clean vault-rotate-db
vault-status: ## Vault sys/health JSON (works on standby via ?standbyok=true)
	$(call vault-pf)
	@curl -sf $(VAULT_TOKEN_HDR) "$(VAULT_API)/v1/sys/health?standbyok=true" | python3 -m json.tool
	$(call vault-pf-stop)

vault-db-creds: ## Read dynamic DB creds from Vault (APP=payments-app)
	$(call vault-pf)
	@curl -sf $(VAULT_TOKEN_HDR) $(VAULT_API)/v1/$(APP)/database/creds/payments | python3 -m json.tool
	$(call vault-pf-stop)

vault-pki-roots: ## Show PKI CA chain (APP=payments-app)
	$(call vault-pf)
	@curl -sf $(VAULT_TOKEN_HDR) $(VAULT_API)/v1/$(APP)/server/pki/cert/ca_chain | python3 -m json.tool
	$(call vault-pf-stop)

vault-lease-clean: ## Force-revoke all DB leases (APP=payments-app)
	$(call vault-pf)
	@curl -sf $(VAULT_TOKEN_HDR) $(VAULT_API)/v1/sys/leases/revoke-force/$(APP)/database -X PUT
	@echo "✓ Leases revoked"
	$(call vault-pf-stop)

vault-rotate-db: ## Rotate DB root credentials (APP=payments-app)
	$(call vault-pf)
	@curl -sf $(VAULT_TOKEN_HDR) $(VAULT_API)/v1/$(APP)/database/rotate-root/payments -X PUT
	@echo "✓ DB root credentials rotated"
	$(call vault-pf-stop)
