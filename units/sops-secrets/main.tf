resource "aws_kms_key" "sops" {
  description             = "SOPS secrets encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Purpose = "sops" })
}

resource "aws_kms_alias" "sops" {
  name          = "alias/sops-secrets"
  target_key_id = aws_kms_key.sops.key_id
}

resource "aws_iam_policy" "sops_decrypt" {
  name        = "${var.project}-sops-decrypt"
  description = "Allow SOPS decryption for ArgoCD and CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.sops.arn
      }
    ]
  })
}

resource "aws_iam_policy" "sops_encrypt" {
  name        = "${var.project}-sops-encrypt"
  description = "Allow SOPS encryption for developers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.sops.arn
      }
    ]
  })
}

resource "local_file" "sops_config" {
  filename = "${path.module}/.sops.yaml"
  content  = <<-EOF
    creation_rules:
      - kms: "${aws_kms_key.sops.arn}"
        aws_profile: ""
  EOF
}
