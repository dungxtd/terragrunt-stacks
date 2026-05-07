{{/*
  Flagger Linkerd canary CR for one service.
  Args: ctx (root), name, svc.

  Activates only when svc.canary == true.
  Uses Linkerd HTTPRoute (provider=linkerd) so caller-side outbound
  proxies do the traffic split. Webhook-only validation (smoke + load)
  because target pods may have skip-inbound-ports that void Linkerd's
  inbound metric collection.

  Per-service knobs (all optional):
    canary: true
    canaryHealthPath: /actuator/health     (default "/")
    canaryInterval: 30s                    (default)
    canaryThreshold: 5                     (default)
    canaryMaxWeight: 50                    (default)
    canaryStepWeight: 10                   (default)
    canaryLoadDuration: 2m                 (default)
*/}}
{{- define "lib.canary" -}}
{{- $ctx := .ctx -}}
{{- $name := .name -}}
{{- $svc := .svc -}}
{{- if $svc.canary }}
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Values.namespace }}
spec:
  provider: linkerd
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $name }}
  progressDeadlineSeconds: 600
  service:
    port: {{ $svc.servicePort | default $svc.port }}
    targetPort: {{ $svc.port }}
  analysis:
    interval: {{ $svc.canaryInterval | default "30s" }}
    threshold: {{ $svc.canaryThreshold | default 5 }}
    maxWeight: {{ $svc.canaryMaxWeight | default 50 }}
    stepWeight: {{ $svc.canaryStepWeight | default 10 }}
    webhooks:
      - name: smoke-test
        type: pre-rollout
        url: http://loadtester.flagger-system/
        timeout: 30s
        metadata:
          type: bash
          cmd: "curl -sf http://{{ $name }}-canary.{{ $ctx.Values.namespace }}:{{ $svc.servicePort | default $svc.port }}{{ $svc.canaryHealthPath | default "/" }}"
      - name: load-test
        type: rollout
        url: http://loadtester.flagger-system/
        timeout: 5s
        metadata:
          cmd: "hey -z {{ $svc.canaryLoadDuration | default "2m" }} -q 10 -c 2 http://{{ $name }}-canary.{{ $ctx.Values.namespace }}:{{ $svc.servicePort | default $svc.port }}{{ $svc.canaryHealthPath | default "/" }}"
{{- end }}
{{- end }}
