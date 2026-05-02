# Unit targets — Usage: make <apply|destroy|plan>-<unit>

UNIT_LIST := vpc eks kms rds vault vault-config certs argocd linkerd aws-alb github-runner

define unit-rule
.PHONY: apply-$(1) destroy-$(1) plan-$(1)
apply-$(1)  : ## terragrunt apply for $(1)
	cd $(UNITS)/$(1) && terragrunt apply
destroy-$(1): ## terragrunt destroy for $(1)
	cd $(UNITS)/$(1) && terragrunt destroy
plan-$(1)   : ## terragrunt plan for $(1)
	cd $(UNITS)/$(1) && terragrunt plan
endef
$(foreach u,$(UNIT_LIST),$(eval $(call unit-rule,$u)))
