{{/*
이름 규칙: 범용 차트라 차트 이름을 붙이지 않고 릴리스 이름을 그대로 쓴다.
helm install whoami ... 이면 Deployment, Service 이름이 모두 whoami 가 된다.
*/}}
{{- define "generic-app.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-app.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-app.version" -}}
{{- default .Chart.AppVersion .Values.image.tag | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "generic-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "generic-app.labels" -}}
helm.sh/chart: {{ include "generic-app.chart" . }}
{{ include "generic-app.selectorLabels" . }}
app.kubernetes.io/version: {{ include "generic-app.version" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "generic-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "generic-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "generic-app.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/* HPA 를 켜면 minReplicas, 아니면 replicaCount 가 "평소 최소 파드 수" */}}
{{- define "generic-app.minReplicas" -}}
{{- if .Values.autoscaling.enabled }}{{ int .Values.autoscaling.minReplicas }}{{ else }}{{ int .Values.replicaCount }}{{ end }}
{{- end }}

{{/*
잘못된 조합은 렌더링 단계에서 막는다. 클러스터에 올라간 뒤에 알게 되는 것보다 싸다.
*/}}
{{- define "generic-app.validate" -}}
{{- if not .Values.image.repository }}
{{- fail "image.repository 는 필수다" }}
{{- end }}
{{- $sleep := int .Values.shutdown.preStopSleepSeconds }}
{{- $grace := int .Values.shutdown.terminationGracePeriodSeconds }}
{{- if and (gt $sleep 0) (le $grace $sleep) }}
{{- fail (printf "shutdown.terminationGracePeriodSeconds(%d) 는 preStopSleepSeconds(%d) 보다 커야 한다. 같거나 작으면 앱이 SIGTERM 을 처리할 시간 없이 SIGKILL 된다" $grace $sleep) }}
{{- end }}
{{- $pdb := .Values.podDisruptionBudget }}
{{- if and $pdb.enabled (ne (toString $pdb.minAvailable) "") (ne (toString $pdb.maxUnavailable) "") }}
{{- fail "podDisruptionBudget.minAvailable 과 maxUnavailable 은 하나만 지정한다" }}
{{- end }}
{{- if .Values.autoscaling.enabled }}
{{- if gt (int .Values.autoscaling.minReplicas) (int .Values.autoscaling.maxReplicas) }}
{{- fail "autoscaling.minReplicas 가 maxReplicas 보다 크다" }}
{{- end }}
{{- if and (gt (int .Values.autoscaling.targetCPUUtilizationPercentage) 0) (not (dig "requests" "cpu" "" .Values.resources)) }}
{{- fail "CPU 기준 HPA 는 resources.requests.cpu 가 있어야 계산된다" }}
{{- end }}
{{- if and (gt (int .Values.autoscaling.targetMemoryUtilizationPercentage) 0) (not (dig "requests" "memory" "" .Values.resources)) }}
{{- fail "메모리 기준 HPA 는 resources.requests.memory 가 있어야 계산된다" }}
{{- end }}
{{- if and (eq (int .Values.autoscaling.targetCPUUtilizationPercentage) 0) (eq (int .Values.autoscaling.targetMemoryUtilizationPercentage) 0) }}
{{- fail "autoscaling 을 켰다면 CPU 또는 메모리 목표 중 하나는 0 보다 커야 한다" }}
{{- end }}
{{- end }}
{{- if and .Values.otel.enabled (or .Values.otel.headersSecret.name .Values.otel.headersSecret.key) (not (and .Values.otel.headersSecret.name .Values.otel.headersSecret.key)) }}
{{- fail "otel.headersSecret 은 name 과 key 를 함께 지정한다" }}
{{- end }}
{{- end }}

{{/*
affinity 를 그대로 쓰되, preferSpot 을 켜면 nodeAffinity.preferred 목록 끝에 spot 선호 항목을 붙인다.
사용자가 넣은 nodeAffinity 를 덮어쓰지 않기 위해 병합한다.
*/}}
{{- define "generic-app.affinity" -}}
{{- $aff := deepCopy (default dict .Values.affinity) }}
{{- if .Values.karpenter.preferSpot.enabled }}
{{- $na := default dict (get $aff "nodeAffinity") }}
{{- $pref := default list (get $na "preferredDuringSchedulingIgnoredDuringExecution") }}
{{- $expr := dict "key" "karpenter.sh/capacity-type" "operator" "In" "values" (list "spot") }}
{{- $term := dict "weight" (int .Values.karpenter.preferSpot.weight) "preference" (dict "matchExpressions" (list $expr)) }}
{{- $_ := set $na "preferredDuringSchedulingIgnoredDuringExecution" (append $pref $term) }}
{{- $_ := set $aff "nodeAffinity" $na }}
{{- end }}
{{- if $aff }}
{{- toYaml $aff }}
{{- end }}
{{- end }}

{{/*
OTel SDK 표준 환경변수. K8S_* 를 먼저 선언해야 OTEL_RESOURCE_ATTRIBUTES 에서 $(VAR) 로 참조할 수 있다.
*/}}
{{- define "generic-app.otelEnv" -}}
{{- $o := .Values.otel }}
{{- $attrs := list "k8s.pod.name=$(K8S_POD_NAME)" "k8s.namespace.name=$(K8S_NAMESPACE_NAME)" "k8s.node.name=$(K8S_NODE_NAME)" (printf "k8s.deployment.name=%s" (include "generic-app.fullname" .)) (printf "service.version=%s" (include "generic-app.version" .)) }}
{{- with $o.environment }}
{{- $attrs = append $attrs (printf "deployment.environment.name=%s" .) }}
{{- end }}
{{- range $k, $v := $o.resourceAttributes }}
{{- $attrs = append $attrs (printf "%s=%v" $k $v) }}
{{- end }}
- name: K8S_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: K8S_NAMESPACE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: K8S_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: OTEL_SERVICE_NAME
  value: {{ default (include "generic-app.fullname" .) $o.serviceName | quote }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $o.endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ $o.protocol | quote }}
- name: OTEL_TRACES_SAMPLER
  value: {{ $o.sampler | quote }}
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ $o.samplerArg | quote }}
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ join "," $attrs | quote }}
{{- if $o.headersSecret.name }}
- name: OTEL_EXPORTER_OTLP_HEADERS
  valueFrom:
    secretKeyRef:
      name: {{ $o.headersSecret.name }}
      key: {{ $o.headersSecret.key }}
{{- end }}
{{- end }}
