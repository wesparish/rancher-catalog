{{/*
Expand the name of the chart.
*/}}
{{- define "tasks-md-wes.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tasks-md-wes.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tasks-md-wes.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tasks-md-wes.labels" -}}
helm.sh/chart: {{ include "tasks-md-wes.chart" . }}
{{ include "tasks-md-wes.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tasks-md-wes.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tasks-md-wes.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "tasks-md-wes.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "tasks-md-wes.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the tasks PVC to use
*/}}
{{- define "tasks-md-wes.tasksPvcName" -}}
{{- if .Values.persistence.tasks.existingClaim }}
{{- .Values.persistence.tasks.existingClaim }}
{{- else }}
{{- printf "%s-tasks" (include "tasks-md-wes.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Name of the config PVC to use
*/}}
{{- define "tasks-md-wes.configPvcName" -}}
{{- if .Values.persistence.config.existingClaim }}
{{- .Values.persistence.config.existingClaim }}
{{- else }}
{{- printf "%s-config" (include "tasks-md-wes.fullname" .) }}
{{- end }}
{{- end }}
