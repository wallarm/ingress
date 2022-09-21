{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "ingress-nginx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ingress-nginx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{/*
Container SecurityContext.
*/}}
{{- define "controller.containerSecurityContext" -}}
{{- if .Values.controller.containerSecurityContext -}}
{{- toYaml .Values.controller.containerSecurityContext -}}
{{- else -}}
capabilities:
  drop:
  - ALL
  add:
  - NET_BIND_SERVICE
  {{- if .Values.controller.image.chroot }}
  - SYS_CHROOT
  {{- end }}
runAsUser: {{ .Values.controller.image.runAsUser }}
allowPrivilegeEscalation: {{ .Values.controller.image.allowPrivilegeEscalation }}
{{- end }}
{{- end -}}

{{/*
Get specific paths
*/}}
{{- define "wallarm.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/etc/wallarm" -}}
{{- else -}}
{{- printf "/etc/wallarm" -}}
{{- end }}
{{- end -}}

{{- define "wallarm-acl.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/var/lib/wallarm-acl" -}}
{{- else -}}
{{- printf "/var/lib/wallarm-acl" -}}
{{- end }}
{{- end -}}

{{- define "wallarm-cache.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/var/lib/nginx/wallarm" -}}
{{- else -}}
{{- printf "/var/lib/nginx/wallarm" -}}
{{- end }}
{{- end -}}

{{/*
Get specific image
*/}}
{{- define "ingress-nginx.image" -}}
{{- if .chroot -}}
{{- printf "%s-chroot" .image -}}
{{- else -}}
{{- printf "%s" .image -}}
{{- end }}
{{- end -}}

{{/*
Get specific image digest
*/}}
{{- define "ingress-nginx.imageDigest" -}}
{{- if .chroot -}}
{{- if .digestChroot -}}
{{- printf "@%s" .digestChroot -}}
{{- end }}
{{- else -}}
{{ if .digest -}}
{{- printf "@%s" .digest -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified controller name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.controller.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.fullname" .) .Values.controller.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Construct the path for the publish-service.

By convention this will simply use the <namespace>/<controller-name> to match the name of the
service generated.

Users can provide an override for an explicit service they want bound via `.Values.controller.publishService.pathOverride`

*/}}
{{- define "ingress-nginx.controller.publishServicePath" -}}
{{- $defServiceName := printf "%s/%s" "$(POD_NAMESPACE)" (include "ingress-nginx.controller.fullname" .) -}}
{{- $servicePath := default $defServiceName .Values.controller.publishService.pathOverride }}
{{- print $servicePath | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified default backend name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.defaultBackend.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.fullname" .) .Values.defaultBackend.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "ingress-nginx.labels" -}}
helm.sh/chart: {{ include "ingress-nginx.chart" . }}
{{ include "ingress-nginx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/part-of: {{ template "ingress-nginx.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.commonLabels}}
{{ toYaml .Values.commonLabels }}
{{- end }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "ingress-nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress-nginx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the controller service account to use
*/}}
{{- define "ingress-nginx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "ingress-nginx.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "ingress-nginx.wallarmTarantoolPort" -}}3313{{- end -}}
{{- define "ingress-nginx.wallarmTarantoolName" -}}{{ .Values.controller.name }}-wallarm-tarantool{{- end -}}
{{- define "ingress-nginx.wallarmTarantoolCronConfig" -}}{{ template "ingress-nginx.wallarmTarantoolName" . }}-cron{{- end -}}
{{- define "ingress-nginx.wallarmControllerCronConfig" -}}{{ include "ingress-nginx.controller.fullname" . | lower }}-cron{{- end -}}
{{- define "ingress-nginx.wallarmSecret" -}}{{ .Values.controller.name }}-secret{{- end -}}

{{- define "ingress-nginx.wallarmInitContainer.addNode" -}}
- name: addnode
{{- if .Values.controller.wallarm.addnode.image }}
  {{- with .Values.controller.wallarm.addnode.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "wallarm/ingress-ruby:{{ .Values.controller.image.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  command:
  - sh
  - -c
{{- if eq .Values.controller.wallarm.fallback "on"}}
{{ print  "- /opt/wallarm/ruby/usr/share/wallarm-common/synccloud --one-time && /opt/wallarm/ruby/usr/share/wallarm-common/sync-ip-lists --one-time -l STDOUT && /opt/wallarm/ruby/usr/share/wallarm-common/sync-ip-lists-source --one-time -l STDOUT || true" | indent 2}}
{{- else }}
{{ print  "- /opt/wallarm/ruby/usr/share/wallarm-common/synccloud --one-time && /opt/wallarm/ruby/usr/share/wallarm-common/sync-ip-lists --one-time -l STDOUT && /opt/wallarm/ruby/usr/share/wallarm-common/sync-ip-lists-source --one-time -l STDOUT" | indent 2}}
{{- end}}
  env:
  - name: WALLARM_API_HOST
    value: {{ .Values.controller.wallarm.apiHost | default "api.wallarm.com" }}
  - name: WALLARM_API_PORT
    value: {{ .Values.controller.wallarm.apiPort | default "443" | quote }}
  - name: WALLARM_API_USE_SSL
    {{- if or (.Values.controller.wallarm.apiSSL) (eq (.Values.controller.wallarm.apiSSL | toString) "<nil>") }}
    value: "true"
    {{- else }}
    value: "false"
    {{- end }}
  - name: WALLARM_API_TOKEN
    valueFrom:
      secretKeyRef:
        key: token
        name: {{ template "ingress-nginx.wallarmSecret" . }}
  - name: WALLARM_SYNCNODE_OWNER
    value: www-data
  - name: WALLARM_SYNCNODE_GROUP
    value: www-data
  volumeMounts:
  - mountPath: /etc/wallarm
    name: wallarm
  - mountPath: /var/lib/wallarm-acl
    name: wallarm-acl
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.addnode.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmInitContainer.exportEnv" -}}
- name: exportenv
{{- if .Values.controller.wallarm.exportenv.image }}
  {{- with .Values.controller.wallarm.exportenv.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "wallarm/ingress-ruby:{{ .Values.controller.image.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  command: ["sh", "-c", "timeout 10m /opt/wallarm/ruby/usr/share/wallarm-common/export-environment -l STDOUT || true"]
  env:
  - name: WALLARM_INGRESS_CONTROLLER_VERSION
    value: {{ .Chart.Version | quote }}
  volumeMounts:
  - mountPath: /etc/wallarm
    name: wallarm
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.exportenv.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmCronContainer" -}}
- name: cron
{{- if .Values.controller.wallarm.cron.image }}
  {{- with .Values.controller.wallarm.cron.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "wallarm/ingress-ruby:{{ .Values.controller.image.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  command: ["/bin/dumb-init", "--"]
  args: ["/bin/supercronic", "-json", "/opt/cron/crontab"]
  env:
  - name: WALLARM_INGRESS_CONTROLLER_VERSION
    value: {{ .Chart.Version | quote }}
  volumeMounts:
  - mountPath: /etc/wallarm
    name: wallarm
  - mountPath: /var/lib/wallarm-acl
    name: wallarm-acl
  - mountPath: /opt/cron/crontab
    name: wallarm-cron
    subPath: crontab
    readOnly: true
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.cron.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmSyncnodeContainer" -}}
- name: synccloud
{{- if .Values.controller.wallarm.synccloud.image }}
  {{- with .Values.controller.wallarm.synccloud.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "wallarm/ingress-ruby:{{ .Values.controller.image.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  command: ["/bin/dumb-init", "--"]
  args: ["/opt/wallarm/ruby/usr/share/wallarm-common/syncnode", "-p", "-r", "120", "-l", "STDOUT", "-L", "DEBUG"]
  env:
  - name: WALLARM_API_HOST
    value: {{ .Values.controller.wallarm.apiHost | default "api.wallarm.com" }}
  - name: WALLARM_API_PORT
    value: {{ .Values.controller.wallarm.apiPort | default "443" | quote }}
  - name: WALLARM_API_USE_SSL
    {{- if or (.Values.controller.wallarm.apiSSL) (eq (.Values.controller.wallarm.apiSSL | toString) "<nil>") }}
    value: "true"
    {{- else }}
    value: "false"
    {{- end }}
  - name: WALLARM_API_TOKEN
    valueFrom:
      secretKeyRef:
        key: token
        name: {{ template "ingress-nginx.wallarmSecret" . }}
  - name: WALLARM_SYNCNODE_OWNER
    value: www-data
  - name: WALLARM_SYNCNODE_GROUP
    value: www-data
  - name: WALLARM_SYNCNODE_INTERVAL
    value: "{{ .Values.controller.wallarm.synccloud.wallarm_syncnode_interval_sec }}"
  volumeMounts:
  - mountPath: /etc/wallarm
    name: wallarm
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.synccloud.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmCollectdContainer" -}}
- name: collectd
{{- if .Values.controller.wallarm.collectd.image }}
  {{- with .Values.controller.wallarm.collectd.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "wallarm/ingress-collectd:{{ .Values.controller.image.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  volumeMounts:
    - name: wallarm
      mountPath: /etc/wallarm
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.collectd.resources | indent 4 }}
{{- end -}}

{{/*
Create the name of the backend service account to use - only used when podsecuritypolicy is also enabled
*/}}
{{- define "ingress-nginx.defaultBackend.serviceAccountName" -}}
{{- if .Values.defaultBackend.serviceAccount.create -}}
    {{ default (printf "%s-backend" (include "ingress-nginx.fullname" .)) .Values.defaultBackend.serviceAccount.name }}
{{- else -}}
    {{ default "default-backend" .Values.defaultBackend.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiGroup for PodSecurityPolicy.
*/}}
{{- define "podSecurityPolicy.apiGroup" -}}
{{- if semverCompare ">=1.14-0" .Capabilities.KubeVersion.GitVersion -}}
{{- print "policy" -}}
{{- else -}}
{{- print "extensions" -}}
{{- end -}}
{{- end -}}

{{/*
Check the ingress controller version tag is at most three versions behind the last release
*/}}
{{- define "isControllerTagValid" -}}
{{- if not (semverCompare ">=0.27.0-0" .Values.controller.image.tag) -}}
{{- fail "Controller container image tag should be 0.27.0 or higher" -}}
{{- end -}}
{{- end -}}

{{/*
IngressClass parameters.
*/}}
{{- define "ingressClass.parameters" -}}
  {{- if .Values.controller.ingressClassResource.parameters -}}
          parameters:
{{ toYaml .Values.controller.ingressClassResource.parameters | indent 4}}
  {{ end }}
{{- end -}}
