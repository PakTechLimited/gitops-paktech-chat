{{- define "pc.labels" -}}
app.kubernetes.io/part-of: paktech-chat
app.kubernetes.io/instance: {{ .Values.env }}
{{- end -}}
{{- define "pc.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  seccompProfile: {type: RuntimeDefault}
{{- end -}}
{{- define "pc.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities: {drop: [ALL]}
  {{- if .Values.hardening.readOnlyRootFilesystem }}
  readOnlyRootFilesystem: true
  {{- end }}
{{- end -}}
{{- define "pc.secretVolume" -}}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes: {secretProviderClass: paktech-chat-kv}
{{- end -}}
