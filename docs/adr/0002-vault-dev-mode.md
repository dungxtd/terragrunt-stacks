# ADR 0002: Vault production mode

Date: 2026-05-01
Status: Superseded

## Context

Real Vault HA needs raft storage (PVC × 3), KMS auto-unseal, init/unseal ceremony, ACL bootstrap. Production Free Tier EKS (4× t3.small, 20Gi RDS) cannot afford the resources for Vault HA replicas + storage + ops overhead.

## Decision

Production now sets `vault_mode = "ha"` in `stacks/vault-consul/production/env.hcl`.

MiniStack remains on `vault_mode = "dev"` for local bootstrap speed.

## Consequences

- Production Vault uses 3 replicas, integrated Raft storage, PVCs, and AWS KMS auto-unseal.
- Vault pods use IRSA for KMS access.
- Terraform initializes Vault once and stores the root token plus recovery keys in SSM SecureString parameters.
- Production no longer relies on the hardcoded `root` dev token.

## Migration to HA

`units/vault/terragrunt.hcl` switches Helm values to Raft + KMS auto-unseal when `vault_mode = "ha"`, while `units/vault-irsa` owns the AWS IAM role/policy used by the Vault service account. Requires:
- KMS key (already provisioned by `units/kms`)
- 10Gi PVC × 3 storage class
- ACL bootstrap (`vault operator init`, run by Terraform for first init)
- Root token and recovery keys in SSM

Run `make stack-vault-production apply` after backing up any dev-mode secrets.
