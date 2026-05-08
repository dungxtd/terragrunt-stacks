{{/*
  Render Argo Rollouts Rollout + stable/canary Services for one microservice.
  Args: name, svc, ctx.

  Activates when svc.rollout == true.

  Real traffic split via Gateway API plugin (svc.gatewayHttpRoute == true) —
  weights patched on the HTTPRoute rendered by lib.httproute.
  Falls back to replica-weighted canary when gatewayHttpRoute is false.

  Per-service knobs:
    rollout: true
    gatewayHttpRoute: true            enable Gateway API plugin trafficRouting
    rolloutSteps:                     custom canary steps (overrides defaults)
    rolloutProgressDeadlineSeconds:   default 600
    rolloutAnalysisInterval:          default 1m (per-step analysis)
    rolloutAnalysisCount:             default 5
*/}}
{{- define "lib.rollout" -}}
{{- $name := .name -}}
{{- $svc := .svc -}}
{{- $ctx := .ctx -}}
{{- $sa := dig "serviceAccount" false $svc -}}
---
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Values.namespace }}
  labels:
    app: {{ $name }}
    {{- include "lib.labels" (dict "ctx" $ctx) | nindent 4 }}
spec:
  replicas: {{ default 2 $svc.replicas }}
  revisionHistoryLimit: 3
  progressDeadlineSeconds: {{ default 600 $svc.rolloutProgressDeadlineSeconds }}
  progressDeadlineAbort: true
  selector:
    matchLabels:
      app: {{ $name }}
  template:
    metadata:
      labels:
        app: {{ $name }}
      {{- $meshAnnot  := include "lib.mesh"  (dict "ctx" $ctx "svc" $svc) -}}
      {{- $vaultAnnot := include "lib.vault" (dict "ctx" $ctx "svc" $svc) -}}
      {{- if or (trim $meshAnnot) (trim $vaultAnnot) }}
      annotations:
        {{- with $meshAnnot  }}{{ . | nindent 8 }}{{ end }}
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
  strategy:
    canary:
      canaryService: {{ $name }}-canary
      stableService: {{ $name }}
      {{- if $svc.gatewayHttpRoute }}
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:
            httpRoute: {{ $name }}
            namespace: {{ $ctx.Values.namespace }}
      {{- end }}
      {{- with $svc.rolloutSteps }}
      steps:
        {{- toYaml . | nindent 8 }}
      {{- else }}
      steps:
        - setWeight: 10
        - pause: { duration: 30s }
        - analysis:
            templates:
              - templateName: smoke-test
              - templateName: success-rate
            args:
              - name: service-name
                value: {{ $name }}
              - name: namespace
                value: {{ $ctx.Values.namespace }}
              - name: health-path
                value: {{ $svc.canaryHealthPath | default "/" | quote }}
              - name: service-port
                value: {{ $svc.servicePort | default $svc.port | quote }}
        - setWeight: 25
        - pause: { duration: 1m }
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency-p99
            args:
              - name: service-name
                value: {{ $name }}
              - name: namespace
                value: {{ $ctx.Values.namespace }}
        - setWeight: 50
        - pause: { duration: 1m }
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency-p99
            args:
              - name: service-name
                value: {{ $name }}
              - name: namespace
                value: {{ $ctx.Values.namespace }}
        - setWeight: 100
      {{- end }}
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
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}-canary
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
{{- if $svc.gatewayHttpRoute }}
{{ include "lib.httproute" (dict "ctx" $ctx "name" $name "svc" $svc) }}
{{- end }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Values.namespace }}
  labels:
    app: {{ $name }}
    {{- include "lib.labels" (dict "ctx" $ctx) | nindent 4 }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: {{ $name }}
{{- end }}
