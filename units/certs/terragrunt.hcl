include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path   = "${get_repo_root()}/_common/vault_provider.hcl"
  expose = true
}

inputs = {
  organization = "HashiCorp Demo"
}
