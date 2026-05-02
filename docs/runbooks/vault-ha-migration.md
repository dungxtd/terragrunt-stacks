# Runbook: Migrate Vault dev → HA (Raft + KMS auto-unseal)

⚠️ **DESTRUCTIVE.** Destroys current Vault state. Backup secrets first.

## Pre-flight

```bash
# 1. EBS CSI driver installed?
kubectl get csidriver ebs.csi.aws.com || (
  echo "Install EBS CSI add-on first — see docs/ebs-csi-options.md"
  exit 1
)

# 2. Storage class gp3 exists?
kubectl get sc gp3 || kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters: { type: gp3, encrypted: "true" }
volumeBindingMode: WaitForFirstConsumer
EOF

# 3. KMS key alive?
make apply-kms

# 4. Backup current dev secrets
make vault-pf
vault login root
vault kv list -format=json secret/ > /tmp/vault-paths.json
for path in $(jq -r '.[]' /tmp/vault-paths.json); do
  vault kv get -format=json "secret/$path" > "/tmp/vault-backup-${path//\//_}.json"
done
ls -la /tmp/vault-backup-*.json   # KEEP THESE FILES SAFE
```

## Migration

```bash
# 1. Verify source is already set to HA
rg 'vault_mode\\s+=\\s+"ha"' stacks/vault-consul/production/env.hcl

# Review the source diff, then publish it through the normal repo flow.
git diff

# OR apply locally if you want manual control:
cd stacks/vault-consul/production
terragrunt run --target='vault-config' destroy   # remove vault-managed config
terragrunt run --target='vault'        destroy   # destroy dev vault
terragrunt run --target='vault'        apply     # apply HA
```

## Initialize Raft (one-time)

The `vault` unit initializes HA Vault during apply and writes these SSM SecureString parameters:

- `/terragrunt-infra/vault/root-token`
- `/terragrunt-infra/vault/recovery-key-0` through `/terragrunt-infra/vault/recovery-key-4`

Use the commands below only if you need to initialize manually.

```bash
kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=300s

# KMS auto-unseal — recovery keys, not unseal keys
kubectl exec -n vault vault-0 -- vault operator init \
  -recovery-shares=5 -recovery-threshold=3 \
  -format=json > /tmp/vault-init.json

ROOT=$(jq -r '.root_token' /tmp/vault-init.json)

# Stash root token in SSM (KMS-encrypted at rest)
aws ssm put-parameter \
  --name /terragrunt-infra/vault/root-token \
  --type SecureString \
  --value "$ROOT" \
  --overwrite

# Stash recovery keys (5 shares, 3 to restore if KMS revoked)
for i in 0 1 2 3 4; do
  KEY=$(jq -r ".recovery_keys_b64[$i]" /tmp/vault-init.json)
  aws ssm put-parameter \
    --name "/terragrunt-infra/vault/recovery-key-$i" \
    --type SecureString \
    --value "$KEY" \
    --overwrite
done

# Verify
kubectl exec -n vault vault-0 -- vault status        # Sealed: false, HA: active
kubectl exec -n vault vault-0 -- vault operator raft list-peers   # 3 voters

# Wipe local copy
shred -u /tmp/vault-init.json
```

## Re-apply Vault config (PKI, DB engine, K8s auth, ESO role)

```bash
make apply-vault-config
```

## Restore secrets

```bash
export VAULT_TOKEN=$(aws ssm get-parameter --name /terragrunt-infra/vault/root-token \
  --with-decryption --query Parameter.Value --output text)

for f in /tmp/vault-backup-*.json; do
  path=$(basename "$f" .json | sed 's/^vault-backup-//; s/_/\//g')
  data=$(jq -c '.data.data' "$f")
  vault kv put "secret/$path" "$data"
done
```

## Rotate root token (security)

```bash
# Default root token = god mode. Disable after bootstrap, generate fresh on demand.
vault token revoke -self
# Future root needs: vault operator generate-root -init / -nonce / -decode
```

## Restart consumers

```bash
kubectl rollout restart deploy -n payments-app
kubectl rollout restart deploy -n external-secrets
```

## Rollback

```bash
# Revert env.hcl
git revert <commit>
# Apply dev mode back (loses HA data)
make stack-vault-production apply
```

## Risks

| Risk | Mitigation |
|------|-----------|
| Recovery keys lost = unrecoverable Vault if KMS key revoked | Store in 2 SSM regions; print sealed envelope copy |
| RDS dynamic creds lease orphans | `vault lease revoke -prefix payments-app/database/creds/` |
| `payments-app` 401 after Vault restart | rolling restart of consumer deployments |
| Quorum loss | Vault chart enables PDB by default (`server.ha.disruptionBudget`) |
