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
Construct a unique electionID.
Users can provide an override for an explicit electionID if they want via `.Values.controller.electionID`
*/}}
{{- define "ingress-nginx.controller.electionID" -}}
{{- $defElectionID := printf "%s-leader" (include "ingress-nginx.fullname" .) -}}
{{- $electionID := default $defElectionID .Values.controller.electionID -}}
{{- print $electionID -}}
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

{{- define "wallarm.credentials" -}}
- name: WALLARM_API_HOST
  value: {{ .Values.controller.wallarm.apiHost | quote }}
- name: WALLARM_API_PORT
  value: {{ .Values.controller.wallarm.apiPort | toString | quote }}
{{- if hasKey .Values.controller.wallarm "apiSSL" }}
- name: WALLARM_API_USE_SSL
  value: {{ .Values.controller.wallarm.apiSSL | toString | quote }}
{{- end }}
{{- if hasKey .Values.controller.wallarm "apiCaVerify" }}
- name: WALLARM_API_CA_VERIFY
  value: {{ .Values.controller.wallarm.apiCaVerify | toString | quote }}
{{- end }}
- name: WALLARM_API_TOKEN_PATH
  value: "/secrets/wallarm/token"
{{- end -}}

{{- define "ingress-nginx.wallarmInitContainer.addNode" -}}
- name: addnode
{{- if .Values.controller.wallarm.addnode.image }}
  {{- with .Values.controller.wallarm.addnode.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "dkr.wallarm.com/wallarm-node/node-helpers:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["/opt/wallarm/usr/share/wallarm-common/register-node", "--force", "--batch", "--no-export-env" {{- if eq .Values.controller.wallarm.fallback "on" }}, "||", "true" {{- end }}, ";", "timeout", "10m", "/opt/wallarm/usr/share/wallarm-common/export-environment", "-l", "STDOUT", "||", "true"]
  env:
  {{- include "wallarm.credentials" . | nindent 2 }}
  - name: WALLARM_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: WALLARM_SYNCNODE_OWNER
    value: www-data
  - name: WALLARM_SYNCNODE_GROUP
    value: www-data
  - name: WALLARM_INGRESS_CONTROLLER_VERSION
    value: {{ .Chart.Version | quote }}
{{- if .Values.controller.wallarm.nodeGroup }}
  - name: WALLARM_LABELS
    value: "group={{ .Values.controller.wallarm.nodeGroup }}"
{{- end }}
  volumeMounts:
  - mountPath: /opt/wallarm/etc/wallarm
    name: wallarm
  - mountPath: /opt/wallarm/var/lib/wallarm-acl
    name: wallarm-acl
  - mountPath: /secrets/wallarm/token
    name: wallarm-token
    subPath: token
    readOnly: true
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.addnode.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmCronContainer" -}}
- name: cron
{{- if .Values.controller.wallarm.cron.image }}
  {{- with .Values.controller.wallarm.cron.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "dkr.wallarm.com/wallarm-node/node-helpers:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["/usr/local/bin/dumb-init", "--rewrite", "15:9", "--", "/usr/local/bin/supercronic", "-json", "/opt/cron/crontab"]
  env:
  {{- include "wallarm.credentials" . | nindent 2 }}
  - name: WALLARM_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: WALLARM_INGRESS_CONTROLLER_VERSION
    value: {{ .Chart.Version | quote }}
  volumeMounts:
  - mountPath: /opt/wallarm/etc/wallarm
    name: wallarm
  - mountPath: /opt/wallarm/var/lib/wallarm-acl
    name: wallarm-acl
  - mountPath: /opt/cron/crontab
    name: wallarm-cron
    subPath: crontab
    readOnly: true
  - mountPath: /secrets/wallarm/token
    name: wallarm-token
    subPath: token
    readOnly: true
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.cron.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmTokenVolume" -}}
- name: wallarm-token
  secret:
    secretName: {{ ternary .Values.controller.wallarm.existingSecret.secretName (include "ingress-nginx.wallarmSecret" .) .Values.controller.wallarm.existingSecret.enabled }}
    items:
      - key: {{ ternary .Values.controller.wallarm.existingSecret.secretKey "token" .Values.controller.wallarm.existingSecret.enabled }}
        path: token
{{- end -}}

{{- define "ingress-nginx.wallarmCollectdContainer" -}}
- name: collectd
{{- if .Values.controller.wallarm.collectd.image }}
  {{- with .Values.controller.wallarm.collectd.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "dkr.wallarm.com/wallarm-node/node-helpers:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["/opt/wallarm/lib64/ld-linux-x86-64.so.2", "--preload", "/opt/wallarm/usr/lib/python3.8/config-3.8-x86_64-linux-gnu/libpython3.8.so", "/opt/wallarm/usr/sbin/collectd", "-f", "-C", "/opt/wallarm/etc/collectd/wallarm-collectd.conf"]
  volumeMounts:
    - name: wallarm
      mountPath: /opt/wallarm/etc/wallarm
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

{{/*
Extra modules.
*/}}
{{- define "extraModules" -}}

- name: {{ .name }}
  image: {{ .image }}
  {{- if .distroless | default false }}
  command: ['/init_module']
  {{- else }}
  command: ['sh', '-c', '/usr/local/bin/init_module.sh']
  {{- end }}
  {{- if .containerSecurityContext }}
  securityContext: {{ .containerSecurityContext | toYaml | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: {{ toYaml "modules"}}
      mountPath: {{ toYaml "/modules_mount"}}

{{- end -}}
