locals {
  oidc_provider_url = replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")
}

data "aws_iam_policy_document" "vault_assume_role" {
  count = var.enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_role" "vault" {
  count = var.enabled ? 1 : 0

  name               = "${var.project}-vault"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "vault_unseal" {
  count = var.enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [var.vault_unseal_key_arn]
  }
}

resource "aws_iam_policy" "vault_unseal" {
  count = var.enabled ? 1 : 0

  name   = "${var.project}-vault-unseal"
  policy = data.aws_iam_policy_document.vault_unseal[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "vault_unseal" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.vault[0].name
  policy_arn = aws_iam_policy.vault_unseal[0].arn
}
