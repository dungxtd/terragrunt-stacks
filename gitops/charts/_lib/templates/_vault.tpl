{{/*
  Vault Agent Injector annotations.
  Args: ctx, svc.
  Activates only when ctx.Values.secrets == "vault" AND svc.vault is set.
*/}}
{{- define "lib.vault" -}}
{{- $ctx := .ctx -}}
{{- $v := .svc.vault -}}
{{- if and (eq $ctx.Values.secrets "vault") $v }}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ $v.role | quote }}
{{- if $v.secret }}
vault.hashicorp.com/agent-inject-secret-application.properties: {{ $v.secret | quote }}
{{- end }}
{{- if $v.template }}
vault.hashicorp.com/agent-inject-template-application.properties: |
{{ $v.template | indent 2 }}
{{- end }}
{{- end }}
{{- end }}
