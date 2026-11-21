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
{{/*
pc.image renders an application image reference.
Call: {{ include "pc.image" (dict "root" . "name" "api") }}
With image.<name>.digest set it renders registry/repo@sha256:...; otherwise registry/repo:tag.
A malformed digest fails the render instead of reaching the cluster.
*/}}
{{- define "pc.image" -}}
{{- $img := index .root.Values.image .name -}}
{{- if $img.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $img.digest) -}}
{{- fail (printf "image.%s.digest must look like sha256:<64 hex>, got %q" .name $img.digest) -}}
{{- end -}}
{{- printf "%s/%s@%s" .root.Values.image.registry $img.repository $img.digest -}}
{{- else -}}
{{- printf "%s/%s:%s" .root.Values.image.registry $img.repository $img.tag -}}
{{- end -}}
{{- end -}}
