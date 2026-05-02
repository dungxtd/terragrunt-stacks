{{/*
  Pod-level mesh annotations.
  Args: ctx (root context), svc (service map).
  Set svc.mesh: false to skip mesh annotations entirely (e.g. product-db).
*/}}
{{- define "lib.mesh" -}}
{{- $ctx := .ctx -}}
{{- $svc := .svc -}}
{{- $skip := and (hasKey $svc "mesh") (eq (toString $svc.mesh) "false") -}}
{{- if not $skip -}}
{{- if eq $ctx.Values.mesh "linkerd" }}
linkerd.io/inject: enabled
{{- if $svc.linkerdSkipOutboundPorts }}
config.linkerd.io/skip-outbound-ports: {{ $svc.linkerdSkipOutboundPorts | quote }}
{{- end }}
{{- end }}
{{- if eq $ctx.Values.mesh "consul" }}
consul.hashicorp.com/connect-inject: "true"
{{- if $svc.upstreams }}
consul.hashicorp.com/connect-service-upstreams: {{ $svc.upstreams | join "," | quote }}
{{- end }}
{{- else }}
consul.hashicorp.com/connect-inject: "false"
{{- end }}
{{- end }}
{{- end }}
