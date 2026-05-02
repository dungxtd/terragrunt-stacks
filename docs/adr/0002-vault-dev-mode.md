# ADR 0002: Vault dev mode for free tier

Date: 2026-05-01
Status: Accepted (temporary)

## Context

Real Vault HA needs raft storage (PVC × 3), KMS auto-unseal, init/unseal ceremony, ACL bootstrap. Production Free Tier EKS (4× t3.small, 20Gi RDS) cannot afford the resources for Vault HA replicas + storage + ops overhead.

## Decision

Set `vault_mode = "dev"` in `stacks/vault-consul/production/env.hcl`. Single replica, in-memory storage, root token = `"root"`.

## Consequences

- ✅ Zero ops, instant `make ms-bootstrap`
- 🔴 Tokens, secrets, leases lost on pod restart
- 🔴 `root` token is hardcoded — no production-grade auth
- 🔴 Not suitable for storing real secrets

## Migration to HA

Switch `vault_mode = "ha"` in env.hcl. Already wired in `units/vault/terragrunt.hcl` — Helm values automatically switch to raft + KMS auto-unseal block. Requires:
- KMS key (already provisioned by `units/kms`)
- 10Gi PVC × 3 storage class
- ACL bootstrap (`vault operator init`)
- Storing unseal keys in SSM (already wired via `vault_token_cmd`)

Run `make stack-vault-production apply` after the switch.
