# ── Ministack path: plaintext-override mirrored to Secrets Manager ──
# Active when local.use_managed_password == false (override non-empty).
# LocalStack RDS doesn't auto-manage master passwords, so we mirror the
# plaintext value into a Secrets Manager secret using the same JSON
# shape as RDS-managed secrets ({"username","password"}). Downstream
# units (vault-config, app units) keep a single read path.

resource "aws_secretsmanager_secret" "master_override" {
  # checkov:skip=CKV_AWS_149: ministack-only; LocalStack KMS not used. Production path uses RDS-managed secret with default AWS-managed key.
  # checkov:skip=CKV2_AWS_57: ministack-only static dev credential; rotation not applicable to LocalStack/host Postgres.
  count                   = local.use_managed_password ? 0 : 1
  name                    = "${var.project}-rds-master-override"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "master_override" {
  count     = local.use_managed_password ? 0 : 1
  secret_id = aws_secretsmanager_secret.master_override[0].id
  secret_string = jsonencode({
    username = "postgres"
    password = var.master_password_override
  })
}
