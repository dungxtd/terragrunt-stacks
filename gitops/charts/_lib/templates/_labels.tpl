{{- define "lib.labels" -}}
helm.sh/chart: {{ .ctx.Chart.Name }}-{{ .ctx.Chart.Version }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
{{- end }}
