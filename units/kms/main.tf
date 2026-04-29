data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.vault_unseal.json
  tags                    = merge(var.tags, { Purpose = "vault-unseal" })
}

data "aws_iam_policy_document" "vault_unseal" {
  #checkov:skip=CKV_AWS_109:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_111:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_356:KMS key policy resource must be * per AWS requirements
  statement {
    sid    = "RootAdmin"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "VaultUnseal"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:role/terragrunt-deploy"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_kms_key" "sops" {
  description             = "SOPS secrets encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.sops.json
  tags                    = merge(var.tags, { Purpose = "sops-secrets" })
}

data "aws_iam_policy_document" "sops" {
  #checkov:skip=CKV_AWS_109:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_111:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_356:KMS key policy resource must be * per AWS requirements
  statement {
    sid    = "RootAdmin"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "SopsEncryptDecrypt"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:role/terragrunt-deploy"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_alias" "sops" {
  name          = "alias/sops-secrets"
  target_key_id = aws_kms_key.sops.key_id
}

resource "aws_kms_key" "tf_state" {
  description             = "Terraform state encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.tf_state.json
  tags                    = merge(var.tags, { Purpose = "tf-state" })
}

data "aws_iam_policy_document" "tf_state" {
  #checkov:skip=CKV_AWS_109:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_111:KMS root admin requires kms:* to prevent key lockout
  #checkov:skip=CKV_AWS_356:KMS key policy resource must be * per AWS requirements
  statement {
    sid    = "RootAdmin"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformStateEncrypt"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:role/terragrunt-deploy"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_alias" "tf_state" {
  name          = "alias/tf-state"
  target_key_id = aws_kms_key.tf_state.key_id
}
