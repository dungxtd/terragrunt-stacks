#!/usr/bin/env bash
# Wait for AWS controllers (ALB, ebs-csi) to finish reconciling cloud resources.
# Must run BEFORE Terragrunt destroys VPC/EKS, otherwise VPC destroy fails on
# dependent ENIs / security groups still held by load balancers or volumes.
#
# Env: AWS_REGION, CLUSTER_NAME, PROJECT_TAG (all have defaults below)
set -euo pipefail

AWS_REGION=${AWS_REGION:-ap-southeast-1}
CLUSTER_NAME=${CLUSTER_NAME:-terragrunt-infra-eks}
PROJECT_TAG=${PROJECT_TAG:-terragrunt-infra}

VPC=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")

if [ "$VPC" = "None" ] || [ -z "$VPC" ]; then
  echo "no VPC tagged Project=${PROJECT_TAG} — skip"
  exit 0
fi

echo "waiting for LBs to deregister in VPC $VPC..."
for i in $(seq 1 60); do
  LBS=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
    --query "LoadBalancers[?VpcId=='${VPC}'].LoadBalancerArn" --output text)
  [ -z "$LBS" ] && echo "LBs gone" && break
  printf "  (%d/60) waiting...\n" "$i"; sleep 10
done

echo "waiting for EBS volumes to be released..."
for i in $(seq 1 30); do
  VOLS=$(aws ec2 describe-volumes --region "$AWS_REGION" \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --query "Volumes[?State!='deleted'].VolumeId" --output text)
  [ -z "$VOLS" ] && echo "EBS volumes gone" && break
  printf "  (%d/30) waiting: %s\n" "$i" "$VOLS"; sleep 10
done
