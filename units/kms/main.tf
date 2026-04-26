resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Purpose = "vault-unseal" })
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_kms_key" "sops" {
  description             = "SOPS secrets encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Purpose = "sops-secrets" })
}

resource "aws_kms_alias" "sops" {
  name          = "alias/sops-secrets"
  target_key_id = aws_kms_key.sops.key_id
}

resource "aws_kms_key" "tf_state" {
  description             = "Terraform state encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Purpose = "tf-state" })
}

resource "aws_kms_alias" "tf_state" {
  name          = "alias/tf-state"
  target_key_id = aws_kms_key.tf_state.key_id
}
