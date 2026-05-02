# Helm targets — render or install the in-house payments-app chart.
# Values now live at gitops/values/payments-app/<env>.yaml.

HELM_VALUES_DIR := $(GITOPS_DIR)/values/$(APP)
HELM_VALUES_FILE := $(HELM_VALUES_DIR)/production.yaml

.PHONY: helm
helm: ## Install/upgrade payments-app via helm
	helm dep update $(CHART) >/dev/null
	helm upgrade --install $(APP) $(CHART) -f $(HELM_VALUES_FILE) -n $(APP) --create-namespace

.PHONY: helm-template
helm-template: ## Render payments-app chart (dry-run)
	helm dep update $(CHART) >/dev/null
	helm template $(APP) $(CHART) -f $(HELM_VALUES_FILE)

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall payments-app helm release
	helm uninstall $(APP) -n $(APP)
