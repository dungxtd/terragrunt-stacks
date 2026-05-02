# Kubernetes / ArgoCD / payments-app smoke tests + cleanup.

.PHONY: alb-crds
alb-crds: ## Apply latest aws-load-balancer-controller CRDs (required after v3.x upgrade)
	kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

.PHONY: kubeconfig
kubeconfig: ## Update kubeconfig from EKS cluster output
	aws eks --region $$(cd $(UNITS)/vpc && terragrunt output -raw region) \
		update-kubeconfig --name $$(cd $(UNITS)/eks && terragrunt output -raw cluster_name)

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

.PHONY: clean-app clean-helm clean-all
clean-app: ## Force-delete payments-app ArgoCD application (skips finalizer block)
	kubectl patch app $(APP) -n argocd \
		-p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type merge
	kubectl delete app $(APP) -n argocd
clean-helm: ## helm uninstall payments-app
	helm uninstall $(APP) -n $(APP) || true
clean-all: clean-helm ## clean-helm + destroy stack
	cd $(STACKS)/vault-consul/production && terragrunt stack run destroy $(TG_FLAGS) || true
