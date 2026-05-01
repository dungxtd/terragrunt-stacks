# EBS CSI Driver — IAM Options

## Why IAM matters

`aws-ebs-csi-driver` controller pod calls AWS APIs (`CreateVolume`, `AttachVolume`, `DescribeInstances`, etc.) to provision EBS volumes for PVCs. Pods have no AWS credentials by default → `AccessDenied` → PVCs stay `Pending`.

Three ways to grant the perms.

## Option A — IRSA (current)

Pod-scoped role via OIDC federation.

```hcl
addons = {
  aws-ebs-csi-driver = {
    most_recent              = true
    service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    configuration_values = jsonencode({
      defaultStorageClass = { enabled = true }
    })
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.58"

  role_name             = "${var.project}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = var.tags
}
```

**What each line does:**
- `attach_ebs_csi_policy = true` — attaches AWS-managed `AmazonEBSCSIDriverPolicy`. Drop = no perms.
- `oidc_providers.main.provider_arn` — trust this OIDC issuer.
- `namespace_service_accounts` — only `kube-system/ebs-csi-controller-sa` can assume role. Trust scope.
- `role_name` + `tags` — optional, repo convention.

**Pros:** pod-scoped (only CSI pods get EBS perms), AWS-recommended, audit-friendly.
**Cons:** ~14 lines + OIDC dependency.

## Option B — Pod Identity

Newer (2023+). No OIDC dance.

```hcl
addons = {
  eks-pod-identity-agent = { most_recent = true, before_compute = true }  # already in repo
  aws-ebs-csi-driver = {
    most_recent = true
    pod_identity_association = [{
      role_arn        = aws_iam_role.ebs_csi.arn
      service_account = "ebs-csi-controller-sa"
    }]
    configuration_values = jsonencode({
      defaultStorageClass = { enabled = true }
    })
  }
}

resource "aws_iam_role" "ebs_csi" {
  name = "${var.project}-ebs-csi"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

**Pros:** pod-scoped, simpler trust (no OIDC), future-proof.
**Cons:** ~17 lines, requires `eks-pod-identity-agent` addon (already in repo).

## Option C — Node Role (simplest)

Attach EBS policy to worker node IAM role. CSI controller pod inherits creds via IMDS.

```hcl
eks_managed_node_groups = {
  default = {
    ...
    iam_role_additional_policies = {
      ebs_csi = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }
}

addons = {
  aws-ebs-csi-driver = {
    most_recent = true
    configuration_values = jsonencode({
      defaultStorageClass = { enabled = true }
    })
  }
}
```

**Pros:** ~3 lines, no separate role/module.
**Cons:** broader blast radius — every pod on node can call EBS API via IMDS. Single-tenant clusters fine.

## Decision matrix

| Option | Lines | Security | Use when |
|--------|-------|----------|----------|
| A — IRSA | ~14 | Pod-scoped via OIDC | Multi-tenant prod, regulated |
| B — Pod Identity | ~17 | Pod-scoped via Pod Identity | Greenfield clusters |
| C — Node role | ~3 | Node-wide | Single-tenant dev / free-tier prod |

## On `iam` module version

Module: `terraform-aws-modules/iam/aws`
- Latest major: **v5.x** (no v6 exists yet)
- Pin `~> 5.58` = accept any `5.58+` within `5.x`. Gets bug fixes, no breaking changes.
- `aws-alb` unit already uses `~> 5.58` → match for consistency.
- No reason to bump unless v5.59+ ships a fix you need. `~> 5.58` already pulls latest 5.x at apply time.
