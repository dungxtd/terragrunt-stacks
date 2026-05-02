SHELL    := /bin/bash
APP      := payments-app
CHART    := gitops/charts/$(APP)
STACKS   := stacks
UNITS    := units
GITOPS_DIR := gitops
TG_FLAGS := --non-interactive --backend-bootstrap

MINISTACK_NAME          := ministack
MINISTACK_PORT          := 4566
MINISTACK_EP            := http://localhost:$(MINISTACK_PORT)
MINISTACK_EKS_CONTAINER := ministack-eks-terragrunt-infra-eks
MINISTACK_KUBECONFIG    := $(shell pwd)/.kubeconfig-ministack
MINISTACK_COMPOSE       := ministack/docker-compose.yml

include makefiles/stacks.mk
include makefiles/units.mk
include makefiles/helm.mk
include makefiles/k8s.mk
include makefiles/vault.mk
include makefiles/ministack.mk
include makefiles/util.mk

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' makefiles/*.mk Makefile 2>/dev/null | sort | \
		awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.PHONY: plan apply destroy
plan apply destroy: ;@:
