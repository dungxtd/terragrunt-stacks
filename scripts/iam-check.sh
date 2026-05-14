#!/usr/bin/env bash
# Simulate key IAM actions against the currently assumed role.
# Fails if any action is denied — catches missing permissions before apply.
# Reusable: called by both deploy (plan job) and any pre-apply gate.
set -euo pipefail

# assumed-role ARN → IAM role ARN
# arn:aws:sts::ID:assumed-role/ROLE/SESSION → arn:aws:iam::ID:role/ROLE
ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text \
  | sed 's|sts|iam|;s|assumed-role|role|;s|/[^/]*$||')

echo "simulating IAM policy for: $ROLE_ARN"

DENIED=$(aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names \
    eks:CreateCluster eks:DescribeCluster \
    rds:CreateDBInstance rds:DescribeDBInstances \
    kms:CreateKey kms:DescribeKey \
    iam:PassRole iam:CreateRole \
    secretsmanager:CreateSecret \
    ec2:CreateVpc ec2:DescribeVpcs \
  --query 'EvaluationResults[?EvalDecision!=`allowed`].EvalActionName' \
  --output text)

if [ -n "$DENIED" ]; then
  echo "IAM denied: $DENIED" >&2
  exit 1
fi
echo "✓ IAM ok"
