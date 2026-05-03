# Kubernetes / ArgoCD / payments-app smoke tests + cleanup.

.PHONY: alb-crds
alb-crds: ## Apply latest aws-load-balancer-controller CRDs (required after v3.x upgrade)
	kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

AWS_REGION      ?= ap-southeast-1
EKS_CLUSTER     ?= terragrunt-infra-eks
AWS_PROFILE_ARG ?= $(if $(AWS_PROFILE),--profile $(AWS_PROFILE),)

.PHONY: kubeconfig
kubeconfig: ## Update ~/.kube/config from EKS (AWS_PROFILE=terragrunt make kubeconfig)
	aws eks update-kubeconfig \
		--region $(AWS_REGION) \
		--name $(EKS_CLUSTER) \
		$(AWS_PROFILE_ARG)

.PHONY: argocd-password argocd-sync argocd-apps
argocd-password: ## Print initial ArgoCD admin password
	@kubectl get secrets -n argocd argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo
argocd-sync: ; argocd app sync $(APP)             ## Force-sync payments-app via argocd CLI
argocd-apps: ; argocd app list                    ## List ArgoCD apps

.PHONY: test-app test-db test-mesh
test-app: ## curl payments-app via LB hostname
	curl -sk $$(kubectl get svc -n $(APP) $(APP) \
		-o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8081/payments
test-db: ## pg_isready against RDS endpoint
	pg_isready -h $$(cd $(UNITS)/rds && terragrunt output -raw rds_endpoint) -p 5432
test-mesh: ## Probe linkerd-proxy / envoy sidecar in payments-app pod
	kubectl exec -n $(APP) deploy/$(APP) -c linkerd-proxy -- \
		/usr/lib/linkerd/linkerd-identity-end-entity 2>/dev/null || \
	kubectl exec -n $(APP) deploy/$(APP) -c envoy-sidecar -- \
		curl -s localhost:19000/certs 2>/dev/null || \
	echo "No mesh sidecar found"

# Port-forward UIs — both envs (production uses ~/.kube/config, ministack uses MINISTACK_KUBECONFIG)
# Usage: make pf-argocd [KC=~/.kube/config]
KC ?= ~/.kube/config

define pf
	@kubectl --kubeconfig $(KC) port-forward svc/$(1) $(2) -n $(3) >/dev/null 2>&1 & \
		sleep 1 && echo "✓ $(3)/$(1) → localhost:$(subst :, → ,$(2))"
endef

.PHONY: pf-argocd pf-vault pf-linkerd pf-consul pf-app pf-all pf-stop
pf-argocd: ## ArgoCD UI → localhost:8080  (user: admin, pass: make argocd-password)
	$(call pf,argocd-server,8080:80,argocd)

pf-vault: ## Vault UI → localhost:8200
	$(call pf,vault,8200:8200,vault)

pf-linkerd: ## Linkerd viz dashboard → localhost:8084
	$(call pf,web,8084:8084,linkerd-viz)

pf-consul: ## Consul UI → localhost:8500
	$(call pf,consul-ui,8500:80,consul)

pf-app: ## payments-app frontend → localhost:8081
	$(call pf,frontend,8081:80,payments-app)

pf-all: pf-argocd pf-vault pf-linkerd pf-consul pf-app ## Port-forward all UIs

pf-stop: ## Kill all port-forwards
	@lsof -ti :8080,:8200,:8084,:8500,:8081 | xargs kill 2>/dev/null || true
	@echo "✓ All port-forwards stopped"

# Ministack shortcuts (pre-sets KC to ministack kubeconfig)
pf-ms-argocd: KC=$(MINISTACK_KUBECONFIG) ; pf-ms-argocd: pf-argocd ## ArgoCD UI (ministack)
pf-ms-vault:  KC=$(MINISTACK_KUBECONFIG) ; pf-ms-vault:  pf-vault  ## Vault UI (ministack)
pf-ms-app:    KC=$(MINISTACK_KUBECONFIG) ; pf-ms-app:    pf-app    ## payments-app (ministack)
pf-ms-all:    KC=$(MINISTACK_KUBECONFIG) ; pf-ms-all:    pf-argocd pf-vault pf-app ## All UIs (ministack)

.PHONY: clean-app clean-helm clean-all
clean-app: ## Force-delete payments-app ArgoCD application (skips finalizer block)
	kubectl patch app $(APP) -n argocd \
		-p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge
	kubectl delete app $(APP) -n argocd
clean-helm: ## helm uninstall payments-app
	helm uninstall $(APP) -n $(APP) || true
clean-all: clean-helm ## clean-helm + destroy stack
	cd $(STACKS)/vault-consul/production && terragrunt stack run destroy $(TG_FLAGS) || true
