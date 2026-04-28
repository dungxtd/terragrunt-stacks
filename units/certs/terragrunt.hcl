include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address = "http://vault.vault.svc.cluster.local:8200"
  }
}

inputs = {
  vault_address = dependency.vault.outputs.vault_address
  organization  = "HashiCorp Demo"
}
