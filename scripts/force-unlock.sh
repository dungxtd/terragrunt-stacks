#!/usr/bin/env bash
# Force-remove stale Terragrunt DynamoDB state locks for a given bucket/prefix.
# Safe to run repeatedly — no-op if no locks found.
#
# Env: STATE_BUCKET, STATE_PREFIX (both have defaults below)
set -euo pipefail

STATE_BUCKET=${STATE_BUCKET:-tf-state-terragrunt-stacks}
STATE_PREFIX=${STATE_PREFIX:-stacks/vault-consul/production}

echo "scanning DynamoDB tf-state-lock for prefix ${STATE_BUCKET}/${STATE_PREFIX}..."
LOCKS=$(aws dynamodb scan \
  --table-name tf-state-lock \
  --filter-expression "begins_with(LockID, :prefix)" \
  --expression-attribute-values "{\":prefix\":{\"S\":\"${STATE_BUCKET}/${STATE_PREFIX}\"}}" \
  --query "Items[].LockID.S" \
  --output text)

if [ -z "$LOCKS" ]; then
  echo "no stale locks found"
  exit 0
fi

for LOCK_ID in $LOCKS; do
  echo "deleting lock: $LOCK_ID"
  aws dynamodb delete-item \
    --table-name tf-state-lock \
    --key "{\"LockID\":{\"S\":\"${LOCK_ID}\"}}"
done
echo "all locks cleared"
