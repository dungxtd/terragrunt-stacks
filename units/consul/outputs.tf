output "consul_address" {
  description = "Consul internal address"
  value       = "http://consul-server.consul.svc.cluster.local:8500"
}

output "consul_datacenter" {
  description = "Consul datacenter name"
  value       = var.datacenter
}

output "consul_namespace" {
  description = "Kubernetes namespace for Consul"
  value       = "consul"
}

output "consul_token" {
  description = "Consul bootstrap ACL token (retrieve after install)"
  value       = ""
  sensitive   = true
}
