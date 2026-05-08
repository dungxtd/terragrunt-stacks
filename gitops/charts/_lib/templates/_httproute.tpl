{{/*
  Render Gateway API HTTPRoute for Linkerd traffic split (parentRef = stable Service).
  Argo Rollouts gateway-api plugin patches backendRefs[*].weight during canary.
  Args: name, svc, ctx.
*/}}
{{- define "lib.httproute" -}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .name }}
  namespace: {{ .ctx.Values.namespace }}
  labels:
    app: {{ .name }}
    {{- include "lib.labels" (dict "ctx" .ctx) | nindent 4 }}
spec:
  parentRefs:
    - name: {{ .name }}
      kind: Service
      group: ""
      port: {{ .svc.servicePort | default .svc.port }}
  rules:
    - backendRefs:
        - name: {{ .name }}
          port: {{ .svc.servicePort | default .svc.port }}
          weight: 100
        - name: {{ .name }}-canary
          port: {{ .svc.servicePort | default .svc.port }}
          weight: 0
{{- end }}
