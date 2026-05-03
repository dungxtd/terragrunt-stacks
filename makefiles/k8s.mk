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

pf-product-db: ## product-db → localhost:5433  (connect: psql -h localhost -p 5433 -U postgres -d products)
	$(call pf,product-db,5433:5432,payments-app)

# RDS is in a private subnet — ExternalName svc has no pod, kubectl port-forward won't work.
# pf-rds spins up a socat proxy pod that bridges localhost:5432 → RDS, then port-forwards it.
# Creds: make vault-db-creds  (or DB_USER/DB_PASS env vars)
.PHONY: pf-rds pf-rds-stop
pf-rds: ## RDS → localhost:5432 via socat proxy pod  (run: make vault-db-creds first)
	@kubectl --kubeconfig $(KC) get pod rds-proxy -n payments-app >/dev/null 2>&1 && \
		echo "rds-proxy already running" || \
	kubectl --kubeconfig $(KC) run rds-proxy -n payments-app --restart=Never \
		--image=alpine/socat -- \
		TCP-LISTEN:5432,fork,reuseaddr TCP:payments-app-database:5432
	@echo "Waiting for rds-proxy pod…"; \
		kubectl --kubeconfig $(KC) wait pod/rds-proxy -n payments-app \
		--for=condition=Ready --timeout=30s
	@kubectl --kubeconfig $(KC) port-forward pod/rds-proxy 5432:5432 -n payments-app >/dev/null 2>&1 & \
		sleep 1 && echo "✓ RDS → localhost:5432 (user: \$$DB_USER, db: payments)"

pf-rds-stop: ## Tear down socat proxy pod + kill port-forward on :5432
	@lsof -ti :5432 | xargs kill 2>/dev/null || true
	@kubectl --kubeconfig $(KC) delete pod rds-proxy -n payments-app --ignore-not-found
	@echo "✓ rds-proxy stopped"

pf-all: pf-argocd pf-vault pf-linkerd pf-consul pf-app pf-product-db ## Port-forward all UIs

pf-stop: ## Kill all port-forwards (UIs + DBs)
	@lsof -ti :8080,:8200,:8084,:8500,:8081,:5432,:5433 | xargs kill 2>/dev/null || true
	@kubectl --kubeconfig $(KC) delete pod rds-proxy -n payments-app --ignore-not-found 2>/dev/null || true
	@echo "✓ All port-forwards stopped"

# Ministack shortcuts (pre-sets KC to ministack kubeconfig)
pf-ms-argocd: KC=$(MINISTACK_KUBECONFIG) ; pf-ms-argocd: pf-argocd ## ArgoCD UI (ministack)
pf-ms-vault:  KC=$(MINISTACK_KUBECONFIG) ; pf-ms-vault:  pf-vault  ## Vault UI (ministack)
pf-ms-app:    KC=$(MINISTACK_KUBECONFIG) ; pf-ms-app:    pf-app    ## payments-app (ministack)
pf-ms-all:    KC=$(MINISTACK_KUBECONFIG) ; pf-ms-all:    pf-argocd pf-vault pf-app ## All UIs (ministack)

.PHONY: db-shell-rds db-shell-product

db-shell-rds: ## psql into RDS via jump pod (gets dynamic creds from Vault)
	@set -e; \
	TOKEN=$$(kubectl --kubeconfig $(KC) get secret -n vault vault-root-token \
		-o jsonpath='{.data.token}' 2>/dev/null | base64 -d); \
	CREDS=$$(kubectl --kubeconfig $(KC) exec -n vault vault-0 -- \
		env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$$TOKEN \
		vault read -format=json payments-app/database/creds/payments); \
	DB_USER=$$(echo "$$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])"); \
	DB_PASS=$$(echo "$$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['password'])"); \
	echo "Connecting as $$DB_USER …"; \
	kubectl --kubeconfig $(KC) run psql-jump -it --rm --restart=Never -n payments-app \
		--image=postgres:15 --env="PGPASSWORD=$$DB_PASS" -- \
		psql -h payments-app-database -U "$$DB_USER" -d payments

db-shell-product: ## psql into product-db via jump pod (static creds)
	kubectl --kubeconfig $(KC) run psql-jump -it --rm --restart=Never -n payments-app \
		--image=postgres:15 --env="PGPASSWORD=password" -- \
		psql -h product-db -U postgres -d products

.PHONY: clean-app clean-helm clean-all
clean-app: ## Force-delete payments-app ArgoCD application (skips finalizer block)
	kubectl patch app $(APP) -n argocd \
		-p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge
	kubectl delete app $(APP) -n argocd
clean-helm: ## helm uninstall payments-app
	helm uninstall $(APP) -n $(APP) || true
clean-all: clean-helm ## clean-helm + destroy stack
	cd $(STACKS)/vault-consul/production && terragrunt stack run destroy $(TG_FLAGS) || true
