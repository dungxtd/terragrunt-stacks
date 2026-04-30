# ── Kubernetes Auth Backend ──────────────────────────────────────

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert
}

# ── Transit Engine ───────────────────────────────────────────────

resource "vault_mount" "transit" {
  path = "transit"
  type = "transit"
}

resource "vault_transit_secret_backend_key" "payments" {
  backend = vault_mount.transit.path
  name    = "payments-app"
}

# ── Database Secrets Engine ──────────────────────────────────────

locals {
  db_endpoint = var.rds_endpoint
  db_username = var.rds_username
  db_password = var.rds_password
}

resource "vault_mount" "database" {
  path = "payments-app/database"
  type = "database"
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.database.path
  name          = "payments"
  allowed_roles = ["payments"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${local.db_endpoint}/payments?sslmode=require"
    username       = local.db_username
    password       = local.db_password
  }
}

resource "vault_database_secret_backend_role" "payments" {
  backend = vault_mount.database.path
  name    = "payments"
  db_name = vault_database_secret_backend_connection.postgres.name

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]

  revocation_statements = [
    "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";",
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]

  default_ttl = 3600
  max_ttl     = 86400
}

# ── KV v2 for payments-processor static creds ────────────────────

resource "vault_mount" "payments_processor" {
  path = "payments-processor/static"
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "payments_processor_creds" {
  mount = vault_mount.payments_processor.path
  name  = "creds"

  data_json = jsonencode({
    username   = "admin"
    password   = var.payments_processor_password
    vault_addr = var.vault_address
  })
}

# ── Vault Policies ───────────────────────────────────────────────

resource "vault_policy" "payments_app" {
  name = "payments-app"

  policy = <<-EOT
    path "payments-app/database/creds/payments" {
      capabilities = ["read"]
    }
    path "transit/encrypt/payments-app" {
      capabilities = ["update"]
    }
    path "transit/decrypt/payments-app" {
      capabilities = ["update"]
    }
    path "sys/leases/renew" {
      capabilities = ["create"]
    }
    path "sys/leases/revoke" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_policy" "payments_processor" {
  name = "payments-processor"

  policy = <<-EOT
    path "payments-processor/static/data/creds" {
      capabilities = ["read"]
    }
  EOT
}

# ── Kubernetes Auth Roles ────────────────────────────────────────

resource "vault_kubernetes_auth_backend_role" "payments_app" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "payments"
  bound_service_account_names      = ["payments-app"]
  bound_service_account_namespaces = ["payments-app"]
  token_policies                   = [vault_policy.payments_app.name]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "payments_processor" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "payments-processor"
  bound_service_account_names      = ["payments-processor"]
  bound_service_account_namespaces = ["payments-app"]
  token_policies                   = [vault_policy.payments_processor.name]
  token_ttl                        = 3600
}
