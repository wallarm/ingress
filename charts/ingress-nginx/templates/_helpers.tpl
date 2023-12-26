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
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "ingress-nginx.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- .Release.Namespace -}}
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
{{- printf "/chroot/opt/wallarm/etc/wallarm" -}}
{{- else -}}
{{- printf "/opt/wallarm/etc/wallarm" -}}
{{- end }}
{{- end -}}

{{- define "wallarm-acl.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/opt/wallarm/var/lib/wallarm-acl" -}}
{{- else -}}
{{- printf "/opt/wallarm/var/lib/wallarm-acl" -}}
{{- end }}
{{- end -}}

{{- define "wallarm-cache.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/opt/wallarm/var/lib/nginx/wallarm" -}}
{{- else -}}
{{- printf "/opt/wallarm/var/lib/nginx/wallarm" -}}
{{- end }}
{{- end -}}

{{- define "wallarm-apifw.path" -}}
{{- if .Values.controller.image.chroot -}}
{{- printf "/chroot/opt/wallarm/var/lib/wallarm-api" -}}
{{- else -}}
{{- printf "/opt/wallarm/var/lib/wallarm-api" -}}
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
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: [ "register" {{- if eq .Values.controller.wallarm.fallback "on" }}, "fallback"{{- end }} ]
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
  - mountPath: {{ include "wallarm.path" . }}
    name: wallarm
  - mountPath: {{ include "wallarm-acl.path" . }}
    name: wallarm-acl
  - mountPath: {{ include "wallarm-apifw.path" . }}
    name: wallarm-apifw
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
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["cron"]
  env:
  {{- include "wallarm.credentials" . | nindent 2 }}
  - name: WALLARM_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: WALLARM_INGRESS_CONTROLLER_VERSION
    value: {{ .Chart.Version | quote }}
  volumeMounts:
  - mountPath: {{ include "wallarm.path" . }}
    name: wallarm
  - mountPath: {{ include "wallarm-acl.path" . }}
    name: wallarm-acl
  - mountPath: {{ include "wallarm-apifw.path" . }}
    name: wallarm-apifw
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
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["collectd"]
  volumeMounts:
    - name: wallarm
      mountPath: {{ include "wallarm.path" . }}
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.collectd.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmApifirewallContainer" -}}
- name: api-firewall
{{- if .Values.controller.wallarm.apifirewall.image }}
  {{- with .Values.controller.wallarm.apifirewall.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["api-firewall"]
  env:
    - name: APIFW_SPECIFICATION_UPDATE_PERIOD
      value: "{{ .Values.controller.wallarm.apifirewall.config.specificationUpdatePeriod }}"
    - name: API_MODE_UNKNOWN_PARAMETERS_DETECTION
      value: "{{ .Values.controller.wallarm.apifirewall.config.unknownParametersDetection }}"
    - name: APIFW_URL
      value: "http://0.0.0.0:{{ .Values.controller.wallarm.apifirewall.config.mainPort }}"
    - name: APIFW_HEALTH_HOST
      value: "0.0.0.0:{{ .Values.controller.wallarm.apifirewall.config.healthPort }}"
    - name: APIFW_LOG_LEVEL
      value: "{{ .Values.controller.wallarm.apifirewall.config.logLevel }}"
    - name: APIFW_LOG_FORMAT
      value: "{{ .Values.controller.wallarm.apifirewall.config.logFormat }}"
    - name: APIFW_MODE
      value: api
    - name: APIFW_READ_TIMEOUT
      value: 5s
    - name: APIFW_WRITE_TIMEOUT
      value: 5s
    - name: APIFW_API_MODE_DEBUG_PATH_DB
      value: "/opt/wallarm/var/lib/wallarm-api/1/wallarm_api.db"
  volumeMounts:
    - name: wallarm-apifw
      mountPath: {{ include "wallarm-apifw.path" . }}
  securityContext: {{ include "controller.containerSecurityContext" . | nindent 4 }}
  resources: {{ toYaml .Values.controller.wallarm.apifirewall.resources | nindent 4 }}
{{- if .Values.controller.wallarm.apifirewall.livenessProbeEnabled }}
  livenessProbe: {{ toYaml .Values.controller.wallarm.apifirewall.livenessProbe | nindent 4 }}
{{- end }}
{{- if .Values.controller.wallarm.apifirewall.readinessProbeEnabled }}
  readinessProbe: {{ toYaml .Values.controller.wallarm.apifirewall.readinessProbe | nindent 4 }}
{{- end }}
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
  {{- if .resources }}
  resources: {{ .resources | toYaml | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: {{ toYaml "modules"}}
      mountPath: {{ toYaml "/modules_mount"}}
{{- end -}}
