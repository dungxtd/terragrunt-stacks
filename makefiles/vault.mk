# Vault + Consul HTTP API helpers via local port-forward.

VAULT_PF_PORT := 18200
VAULT_CURL    := curl -sf -H "X-Vault-Token: root" http://localhost:$(VAULT_PF_PORT)

define vault-pf
	@KUBECONFIG=$(MINISTACK_KUBECONFIG) kubectl port-forward svc/vault $(VAULT_PF_PORT):8200 -n vault >/dev/null 2>&1 & sleep 2
endef
define vault-pf-stop
	@lsof -ti :$(VAULT_PF_PORT) | xargs kill 2>/dev/null || true
endef

.PHONY: vault-status vault-db-creds vault-pki-roots vault-lease-clean vault-rotate-db
vault-status: ## Vault sys/health JSON
	$(call vault-pf)
	@$(VAULT_CURL)/v1/sys/health | python3 -m json.tool
	$(call vault-pf-stop)

vault-db-creds: ## Read dynamic DB creds from Vault
	$(call vault-pf)
	@$(VAULT_CURL)/v1/$(APP)/database/creds/payments | python3 -m json.tool
	$(call vault-pf-stop)

vault-pki-roots: ## Show Consul PKI CA chain
	$(call vault-pf)
	@$(VAULT_CURL)/v1/consul/server/pki/cert/ca_chain | python3 -m json.tool
	$(call vault-pf-stop)

vault-lease-clean: ## Force-revoke all DB leases
	$(call vault-pf)
	@$(VAULT_CURL)/v1/sys/leases/revoke-force/$(APP)/database -X PUT
	@echo "✓ Leases revoked"
	$(call vault-pf-stop)

vault-rotate-db: ## Rotate DB root credentials
	$(call vault-pf)
	@$(VAULT_CURL)/v1/$(APP)/database/rotate-root/payments -X PUT
	@echo "✓ DB root credentials rotated"
	$(call vault-pf-stop)

.PHONY: consul-members consul-intentions consul-ca-roots
consul-members:    ; consul members            ## consul members
consul-intentions: ; consul intention list     ## consul intention list
consul-ca-roots: ## Consul Connect CA roots
	curl -sk -H "X-Consul-Token:$${CONSUL_HTTP_TOKEN}" \
		$${CONSUL_HTTP_ADDR}/v1/connect/ca/roots | jq .
