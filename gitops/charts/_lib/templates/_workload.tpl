{{/*
  Render Deployment + Service for one microservice.
  Args:
    name: service name (k8s resource name + label selector)
    svc:  service config map (image, port, replicas, env, probes, vault, sa, ...)
    ctx:  root chart context (.)

  Service rendered only if svc.service != false.
  Service rendered only if svc.serviceAccount truthy ("" or true → name; string → custom).
*/}}
{{- define "lib.workload" -}}
{{- $name := .name -}}
{{- $svc := .svc -}}
{{- $ctx := .ctx -}}
{{- $sa := dig "serviceAccount" false $svc -}}
{{- $renderService := ne (toString (default true $svc.service)) "false" -}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Values.namespace }}
  labels:
    app: {{ $name }}
    {{- include "lib.labels" (dict "ctx" $ctx) | nindent 4 }}
spec:
  replicas: {{ default 1 $svc.replicas }}
  selector:
    matchLabels:
      app: {{ $name }}
  template:
    metadata:
      labels:
        app: {{ $name }}
      {{- $meshAnnot := include "lib.mesh" (dict "ctx" $ctx "svc" $svc) -}}
      {{- $vaultAnnot := include "lib.vault" (dict "ctx" $ctx "svc" $svc) -}}
      {{- if or (trim $meshAnnot) (trim $vaultAnnot) }}
      annotations:
        {{- with $meshAnnot }}{{ . | nindent 8 }}{{ end }}
        {{- with $vaultAnnot }}{{ . | nindent 8 }}{{ end }}
      {{- end }}
    spec:
      {{- if $sa }}
      serviceAccountName: {{ if eq (toString $sa) "true" }}{{ $name }}{{ else }}{{ $sa }}{{ end }}
      {{- end }}
      containers:
        - name: {{ $name }}
          image: {{ $svc.image }}
          ports:
            - containerPort: {{ $svc.port }}
              name: {{ default "http" $svc.portName }}
          {{- with $svc.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with $svc.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- if $renderService }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Values.namespace }}
  labels:
    app: {{ $name }}
    {{- include "lib.labels" (dict "ctx" $ctx) | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    app: {{ $name }}
  ports:
    - port: {{ default $svc.port $svc.servicePort }}
      targetPort: {{ $svc.port }}
      name: {{ default "http" $svc.portName }}
{{- end }}
{{- end }}
