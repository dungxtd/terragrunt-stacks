# Stack targets — env detected from directory; no flag needed.
# Usage: make stack-vault-<env> <plan|apply|destroy>

define stack-rule
.PHONY: stack-$(1)-$(2) stack-$(1)-$(2)-generate
stack-$(1)-$(2)-generate: ## Generate $(1) stack ($(2))
	cd $(STACKS)/$(3)/$(2) && terragrunt stack generate $(TG_FLAGS)
stack-$(1)-$(2): ## Run $(1) stack ($(2)) — append plan|apply|destroy
	$$(eval ACTION := $$(filter plan apply destroy,$$(MAKECMDGOALS)))
	@if [ -z "$$(ACTION)" ]; then echo "Usage: make stack-$(1)-$(2) <plan|apply|destroy>"; exit 1; fi
	cd $(STACKS)/$(3)/$(2) && terragrunt stack generate $(TG_FLAGS) && terragrunt stack run $$(ACTION) $(TG_FLAGS)
endef

$(eval $(call stack-rule,vault,production,vault-consul))
$(eval $(call stack-rule,vault,ministack,vault-consul))
