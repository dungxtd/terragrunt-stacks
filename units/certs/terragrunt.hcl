include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address    = "http://vault.vault.svc.cluster.local:8200"
    vault_root_token = "mock-token"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vault_address = dependency.vault.outputs.vault_address
  vault_token   = dependency.vault.outputs.vault_root_token
  organization  = "HashiCorp Demo"
}
