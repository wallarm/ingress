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
Expand the namespace of the release.
Allows overriding it for multi-namespace deployments in combined charts.
*/}}
{{- define "ingress-nginx.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Controller container security context.
*/}}
{{- define "ingress-nginx.controller.containerSecurityContext" -}}
{{- if .Values.controller.containerSecurityContext -}}
{{- toYaml .Values.controller.containerSecurityContext -}}
{{- else -}}
runAsNonRoot: {{ .Values.controller.image.runAsNonRoot }}
runAsUser: {{ .Values.controller.image.runAsUser }}
allowPrivilegeEscalation: {{ or .Values.controller.image.allowPrivilegeEscalation .Values.controller.image.chroot }}
{{- if .Values.controller.image.seccompProfile }}
seccompProfile: {{ toYaml .Values.controller.image.seccompProfile | nindent 2 }}
{{- end }}
capabilities:
  drop:
  - ALL
  add:
  - NET_BIND_SERVICE
  {{- if .Values.controller.image.chroot }}
  {{- if .Values.controller.image.seccompProfile }}
  - SYS_ADMIN
  {{- end }}
  - SYS_CHROOT
  {{- end }}
readOnlyRootFilesystem: {{ .Values.controller.image.readOnlyRootFilesystem }}
{{- end -}}
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

{{- define "ingress-nginx.wallarmPostanalyticsPort" -}}3313{{- end -}}
{{- define "ingress-nginx.wallarmPostanalyticsName" -}}{{ .Values.controller.name }}-wallarm-wstore{{- end -}}
{{- define "ingress-nginx.wallarmPostanalyticsWcliConfig" -}}{{ template "ingress-nginx.wallarmPostanalyticsName" . }}-wcli{{- end -}}
{{- define "ingress-nginx.wallarmControllerWcliConfig" -}}{{ include "ingress-nginx.controller.fullname" . | lower }}-wcli{{- end -}}
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
- name: WALLARM_COMPONENT_NAME
  value: wallarm-ingress-controller
- name: WALLARM_COMPONENT_VERSION
  value: {{ .Chart.Version | quote }}
{{- end -}}

{{- define "ingress-nginx.wallarmInitContainer.init" -}}
- name: init
{{- if .Values.controller.wallarm.init.image }}
  {{- with .Values.controller.wallarm.init.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: [ "register", "{{ .Values.register_mode }}" {{- if eq .Values.controller.wallarm.fallback "on" }}, "fallback"{{- end }} ]
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
{{- if .Values.controller.wallarm.nodeGroup }}
  - name: WALLARM_LABELS
    value: "group={{ .Values.controller.wallarm.nodeGroup }}"
{{- end }}
{{- if .Values.controller.wallarm.init.extraEnvs }}
  {{- toYaml .Values.controller.wallarm.init.extraEnvs | nindent 2 }}
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
  securityContext: {{ include "ingress-nginx.controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.init.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmWcliContainer" -}}
- name: wcli
{{- if .Values.controller.wallarm.wcli.image }}
  {{- with .Values.controller.wallarm.wcli.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["wcli", "run", {{ include "ingress-nginx.wcli-args" . }}]
  env:
  {{- include "wallarm.credentials" . | nindent 2 }}
  - name: WALLARM_NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
{{- if .Values.controller.wallarm.wcli.extraEnvs }}
  {{- toYaml .Values.controller.wallarm.wcli.extraEnvs | nindent 2 }}
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
  securityContext: {{ include "ingress-nginx.controller.containerSecurityContext" . | nindent 4 }}
  resources:
{{ toYaml .Values.controller.wallarm.wcli.resources | indent 4 }}
{{- end -}}

{{- define "ingress-nginx.wallarmTokenVolume" -}}
- name: wallarm-token
  secret:
    secretName: {{ ternary .Values.controller.wallarm.existingSecret.secretName (include "ingress-nginx.wallarmSecret" .) .Values.controller.wallarm.existingSecret.enabled }}
    items:
      - key: {{ ternary .Values.controller.wallarm.existingSecret.secretKey "token" .Values.controller.wallarm.existingSecret.enabled }}
        path: token
{{- end -}}

{{- define "ingress-nginx.wallarmapiFirewallContainer" -}}
- name: api-firewall
{{- if .Values.controller.wallarm.apiFirewall.image }}
  {{- with .Values.controller.wallarm.apiFirewall.image }}
  image: "{{ .repository }}:{{ .tag }}"
  {{- end }}
{{- else }}
  image: "{{ .Values.controller.wallarm.helpers.image }}:{{ .Values.controller.wallarm.helpers.tag }}"
{{- end }}
  imagePullPolicy: "{{ .Values.controller.image.pullPolicy }}"
  args: ["api-firewall"]
  env:
    - name: APIFW_SPECIFICATION_UPDATE_PERIOD
      value: "{{ .Values.controller.wallarm.apiFirewall.config.specificationUpdatePeriod }}"
    - name: API_MODE_UNKNOWN_PARAMETERS_DETECTION
      value: "{{ .Values.controller.wallarm.apiFirewall.config.unknownParametersDetection }}"
    - name: APIFW_URL
      value: "http://0.0.0.0:{{ .Values.controller.wallarm.apiFirewall.config.mainPort }}"
    - name: APIFW_HEALTH_HOST
      value: "0.0.0.0:{{ .Values.controller.wallarm.apiFirewall.config.healthPort }}"
    - name: APIFW_LOG_LEVEL
      value: "{{ .Values.controller.wallarm.apiFirewall.config.logLevel }}"
    - name: APIFW_LOG_FORMAT
      value: "{{ .Values.controller.wallarm.apiFirewall.config.logFormat }}"
    - name: APIFW_MODE
      value: api
    - name: APIFW_READ_TIMEOUT
      value: 5s
    - name: APIFW_WRITE_TIMEOUT
      value: 5s
    - name: APIFW_READ_BUFFER_SIZE
      value: "{{ .Values.controller.wallarm.apiFirewall.readBufferSize | int64 }}"
    - name: APIFW_WRITE_BUFFER_SIZE
      value: "{{ .Values.controller.wallarm.apiFirewall.writeBufferSize | int64 }}"
    - name: APIFW_MAX_REQUEST_BODY_SIZE
      value: "{{ .Values.controller.wallarm.apiFirewall.maxRequestBodySize | int64 }}"
    - name: APIFW_DISABLE_KEEPALIVE
      value: "{{ .Values.controller.wallarm.apiFirewall.disableKeepalive }}"
    - name: APIFW_MAX_CONNS_PER_IP
      value: "{{ .Values.controller.wallarm.apiFirewall.maxConnectionsPerIp }}"
    - name: APIFW_MAX_REQUESTS_PER_CONN
      value: "{{ .Values.controller.wallarm.apiFirewall.maxRequestsPerConnection }}"
    - name: APIFW_API_MODE_DEBUG_PATH_DB
      value: "{{ include "wallarm-apifw.path" . }}/2/wallarm_api.db"
{{- if .Values.controller.wallarm.apiFirewall.extraEnvs }}
    {{- toYaml .Values.controller.wallarm.apiFirewall.extraEnvs | nindent 4 }}
{{- end }}
  volumeMounts:
    - name: wallarm-apifw
      mountPath: {{ include "wallarm-apifw.path" . }}
  securityContext: {{ include "ingress-nginx.controller.containerSecurityContext" . | nindent 4 }}
  resources: {{ toYaml .Values.controller.wallarm.apiFirewall.resources | nindent 4 }}
  ports:
    - name: health
      containerPort: {{ .Values.controller.wallarm.apiFirewall.config.healthPort }}
{{- if .Values.controller.wallarm.apiFirewall.livenessProbeEnabled }}
  livenessProbe: {{ toYaml .Values.controller.wallarm.apiFirewall.livenessProbe | nindent 4 }}
{{- end }}
{{- if .Values.controller.wallarm.apiFirewall.readinessProbeEnabled }}
  readinessProbe: {{ toYaml .Values.controller.wallarm.apiFirewall.readinessProbe | nindent 4 }}
{{- end }}
{{- end -}}

{{/*
Create a default fully qualified admission webhook name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.admissionWebhooks.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.fullname" .) .Values.controller.admissionWebhooks.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the admission webhook patch job service account to use
*/}}
{{- define "ingress-nginx.admissionWebhooks.patch.serviceAccountName" -}}
{{- if .Values.controller.admissionWebhooks.patch.serviceAccount.create -}}
    {{ default (include "ingress-nginx.admissionWebhooks.fullname" .) .Values.controller.admissionWebhooks.patch.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.controller.admissionWebhooks.patch.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified admission webhook secret creation job name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.admissionWebhooks.createSecretJob.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.admissionWebhooks.fullname" .) .Values.controller.admissionWebhooks.createSecretJob.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified admission webhook patch job name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.admissionWebhooks.patchWebhookJob.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.admissionWebhooks.fullname" .) .Values.controller.admissionWebhooks.patchWebhookJob.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified default backend name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ingress-nginx.defaultBackend.fullname" -}}
{{- printf "%s-%s" (include "ingress-nginx.fullname" .) .Values.defaultBackend.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the default backend service account to use
*/}}
{{- define "ingress-nginx.defaultBackend.serviceAccountName" -}}
{{- if .Values.defaultBackend.serviceAccount.create -}}
    {{ default (printf "%s-backend" (include "ingress-nginx.fullname" .)) .Values.defaultBackend.serviceAccount.name }}
{{- else -}}
    {{ default "default-backend" .Values.defaultBackend.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Default backend container security context.
*/}}
{{- define "ingress-nginx.defaultBackend.containerSecurityContext" -}}
{{- if .Values.defaultBackend.containerSecurityContext -}}
{{- toYaml .Values.defaultBackend.containerSecurityContext -}}
{{- else -}}
runAsNonRoot: {{ .Values.defaultBackend.image.runAsNonRoot }}
runAsUser: {{ .Values.defaultBackend.image.runAsUser }}
allowPrivilegeEscalation: {{ .Values.defaultBackend.image.allowPrivilegeEscalation }}
{{- if .Values.defaultBackend.image.seccompProfile }}
seccompProfile: {{ toYaml .Values.defaultBackend.image.seccompProfile | nindent 2 }}
{{- end }}
capabilities:
  drop:
  - ALL
readOnlyRootFilesystem: {{ .Values.defaultBackend.image.readOnlyRootFilesystem }}
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
Extra modules.
*/}}
{{- define "extraModules" -}}
- name: {{ .name }}
  {{- with .image }}
  image: {{ if .repository }}{{ .repository }}{{ else }}{{ .registry }}/{{ .image }}{{ end }}:{{ .tag }}{{ if .digest }}@{{ .digest }}{{ end }}
  command:
  {{- if .distroless }}
    - /init_module
  {{- else }}
    - sh
    - -c
    - /usr/local/bin/init_module.sh
  {{- end }}
  {{- end }}
  {{- if .containerSecurityContext }}
  securityContext: {{ toYaml .containerSecurityContext | nindent 4 }}
  {{- end }}
  {{- if .resources }}
  resources: {{ toYaml .resources | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: modules
      mountPath: /modules_mount
{{- end -}}

{{/*
Wcli arguments building
*/}}
{{- define "ingress-nginx.wcli-args" -}}
"-log-level", "{{ .Values.controller.wallarm.wcli.logLevel }}",{{ " " }}
{{- with .Values.controller.wallarm.wcli.commands -}}
{{- range $name, $value := . -}}
"job:{{ $name }}", "-log-level", "{{ $value.logLevel }}",{{ " " }}
{{- end -}}
{{- end -}}
{{- end -}}
