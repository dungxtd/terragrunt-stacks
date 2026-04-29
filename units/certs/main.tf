# ── Offline Root CA ──────────────────────────────────────────────

resource "tls_private_key" "root_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name  = "Consul Root CA"
    organization = var.organization
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ── Consul Server PKI ───────────────────────────────────────────

resource "vault_mount" "consul_server_root" {
  path                  = "consul/server/pki"
  type                  = "pki"
  max_lease_ttl_seconds = 315360000 # 10 years
}

resource "vault_pki_secret_backend_root_cert" "consul_server_root" {
  backend     = vault_mount.consul_server_root.path
  type        = "internal"
  common_name = "Consul Server Root CA"
  ttl         = "87600h"
}

resource "vault_mount" "consul_server_intermediate" {
  path                  = "consul/server/pki_int"
  type                  = "pki"
  max_lease_ttl_seconds = 157680000 # 5 years
}

resource "vault_pki_secret_backend_intermediate_cert_request" "consul_server" {
  backend     = vault_mount.consul_server_intermediate.path
  type        = "internal"
  common_name = "Consul Server Intermediate CA"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "consul_server" {
  backend     = vault_mount.consul_server_root.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.consul_server.csr
  common_name = "Consul Server Intermediate CA"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "consul_server" {
  backend     = vault_mount.consul_server_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.consul_server.certificate
}

# ── Consul Connect PKI ──────────────────────────────────────────

resource "vault_mount" "consul_connect_root" {
  path                  = "consul/connect/pki"
  type                  = "pki"
  max_lease_ttl_seconds = 315360000
}

resource "vault_pki_secret_backend_root_cert" "consul_connect_root" {
  backend     = vault_mount.consul_connect_root.path
  type        = "internal"
  common_name = "Consul Connect Root CA"
  ttl         = "87600h"
}

resource "vault_mount" "consul_connect_intermediate" {
  path                  = "consul/connect/pki_int"
  type                  = "pki"
  max_lease_ttl_seconds = 157680000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "consul_connect" {
  backend     = vault_mount.consul_connect_intermediate.path
  type        = "internal"
  common_name = "Consul Connect Intermediate CA"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "consul_connect" {
  backend     = vault_mount.consul_connect_root.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.consul_connect.csr
  common_name = "Consul Connect Intermediate CA"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "consul_connect" {
  backend     = vault_mount.consul_connect_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.consul_connect.certificate
}

# ── Consul API Gateway PKI ──────────────────────────────────────

resource "vault_mount" "consul_gateway_root" {
  path                  = "consul/gateway/pki"
  type                  = "pki"
  max_lease_ttl_seconds = 315360000
}

resource "vault_pki_secret_backend_root_cert" "consul_gateway_root" {
  backend     = vault_mount.consul_gateway_root.path
  type        = "internal"
  common_name = "Consul Gateway Root CA"
  ttl         = "87600h"
}

resource "vault_mount" "consul_gateway_intermediate" {
  path                  = "consul/gateway/pki_int"
  type                  = "pki"
  max_lease_ttl_seconds = 157680000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "consul_gateway" {
  backend     = vault_mount.consul_gateway_intermediate.path
  type        = "internal"
  common_name = "Consul Gateway Intermediate CA"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "consul_gateway" {
  backend     = vault_mount.consul_gateway_root.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.consul_gateway.csr
  common_name = "Consul Gateway Intermediate CA"
  ttl         = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "consul_gateway" {
  backend     = vault_mount.consul_gateway_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.consul_gateway.certificate
}

# ── PKI Roles ────────────────────────────────────────────────────

resource "vault_pki_secret_backend_role" "consul_server" {
  backend          = vault_mount.consul_server_intermediate.path
  name             = "consul-server"
  allowed_domains  = ["dc1.consul"]
  allow_subdomains = true
  max_ttl          = "720h"
  generate_lease   = true
}

resource "vault_pki_secret_backend_role" "consul_gateway" {
  backend          = vault_mount.consul_gateway_intermediate.path
  name             = "consul-api-gateway"
  allowed_domains  = ["hashiconf.example.com"]
  allow_subdomains = true
  max_ttl          = "720h"
  generate_lease   = true
}
