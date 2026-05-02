{{/*
  Render an ExternalSecret + (optional) ClusterSecretStore reference.

  Args:
    name:       k8s name of the ExternalSecret AND target Secret (unless target overridden)
    es:         service config map (vaultPath, namespace, target?, dataKeys?, refreshInterval?)
    ctx:        root chart context

  Two modes:
    1. Default — pull ALL fields under Vault path verbatim:
         - vaultPath: datadog/api  →  Secret keys = field names in Vault

    2. Explicit mapping — when k8s key name MUST differ from Vault field name:
         - dataKeys: { api-key: key, app-key: app }
           # left = k8s Secret key, right = Vault field
*/}}
{{- define "lib.externalSecret" -}}
{{- $name := .name -}}
{{- $es   := .es -}}
{{- $ctx  := .ctx -}}
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ $name }}
  namespace: {{ $es.namespace }}
spec:
  refreshInterval: {{ default "1h" $es.refreshInterval }}
  secretStoreRef:
    name: {{ default "vault-backend" $es.secretStore }}
    kind: {{ default "ClusterSecretStore" $es.secretStoreKind }}
  target:
    name: {{ default $name $es.target }}
    creationPolicy: {{ default "Owner" $es.creationPolicy }}
  {{- if $es.dataKeys }}
  data:
    {{- range $k8sKey, $vaultField := $es.dataKeys }}
    - secretKey: {{ $k8sKey }}
      remoteRef:
        key: {{ $es.vaultPath }}
        property: {{ $vaultField }}
    {{- end }}
  {{- else }}
  dataFrom:
    - extract:
        key: {{ $es.vaultPath }}
  {{- end }}
{{- end }}
