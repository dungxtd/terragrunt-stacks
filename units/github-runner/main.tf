# Disabled in all envs (enable_github_runner = false). Enable when self-hosted
# runners are needed: set enable_github_runner = true in env.hcl and provide
# GITHUB_APP_* or GITHUB_PAT env vars.

locals {
  controller_namespace = "arc-systems"
  runner_namespace     = "arc-runners"

  # Auth: prefer GitHub App, fallback to PAT
  use_github_app = var.github_app_id != "" && var.github_app_private_key != ""
}

# ── ARC Controller ─────────────────────────────────────────

resource "helm_release" "arc_controller" {
  count            = var.enabled ? 1 : 0
  name             = "arc"
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  version          = "0.14.0"
  namespace        = local.controller_namespace
  create_namespace = true

  values = [yamlencode({
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]
  })]
}

# ── GitHub App Secret ──────────────────────────────────────

resource "kubernetes_secret" "github_app" {
  count = var.enabled && local.use_github_app ? 1 : 0

  metadata {
    name      = "arc-github-app"
    namespace = local.runner_namespace
  }

  data = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }

  depends_on = [helm_release.arc_controller[0]]
}

# ── PAT Secret ─────────────────────────────────────────────

resource "kubernetes_secret" "github_pat" {
  count = var.enabled && !local.use_github_app ? 1 : 0

  metadata {
    name      = "arc-github-pat"
    namespace = local.runner_namespace
  }

  data = {
    github_token = var.github_pat
  }

  depends_on = [helm_release.arc_controller[0]]
}

# ── Runner Scale Set ───────────────────────────────────────

resource "kubernetes_namespace" "runners" {
  count = var.enabled ? 1 : 0
  metadata {
    name = local.runner_namespace
  }
}

resource "helm_release" "arc_runner_set" {
  count      = var.enabled ? 1 : 0
  name       = var.runner_scale_set_name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.14.0"
  namespace  = local.runner_namespace

  values = [yamlencode({
    githubConfigUrl    = var.github_config_url
    githubConfigSecret = local.use_github_app ? "arc-github-app" : "arc-github-pat"

    minRunners = var.min_runners
    maxRunners = var.max_runners

    containerMode = {
      type = "dind"
    }

    template = {
      spec = {
        serviceAccountName = kubernetes_service_account.runner[0].metadata[0].name
        containers = [{
          name    = "runner"
          image   = "ghcr.io/actions/actions-runner:latest"
          command = ["/home/runner/run.sh"]
          resources = {
            requests = {
              cpu    = var.runner_requests_cpu
              memory = var.runner_requests_memory
            }
            limits = {
              cpu    = var.runner_limits_cpu
              memory = var.runner_limits_memory
            }
          }
        }]
      }
    }

    controllerServiceAccount = {
      namespace = local.controller_namespace
      name      = "arc-gha-rs-controller"
    }
  })]

  depends_on = [
    helm_release.arc_controller[0],
    kubernetes_secret.github_app,
    kubernetes_secret.github_pat,
  ]
}

# ── Runner Service Account (for IRSA) ─────────────────────

resource "kubernetes_service_account" "runner" {
  count = var.enabled ? 1 : 0
  metadata {
    name        = "${var.runner_scale_set_name}-sa"
    namespace   = local.runner_namespace
    annotations = var.runner_service_account_annotations
  }

  depends_on = [kubernetes_namespace.runners[0]]
}
