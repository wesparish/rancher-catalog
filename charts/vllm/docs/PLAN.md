# vLLM Helm Chart Update Plan

## Overview

Update the vLLM helm chart to serve multiple AI models, where **each model gets its own Deployment and NodePort Service**. The chart iterates over a `models` list in `values.yaml` and generates one Deployment + one Service per model.

## Reference: Equivalent docker run

This is the working docker command the chart is modeled after:

```bash
docker run --rm -ti --privileged \
    -v /mnt/ceph-fs/k8s-volumes/ai-models/huggingface:/root/.cache/huggingface \
    -p 8000:8000 \
    --ipc=host \
    --name wes-Qwen3.5-9B-AWQ-32k \
    vllm/vllm-openai:v0.18.0 \
    /root/.cache/huggingface/Qwen3.5-9B-AWQ \
    --served-model-name Qwen3.5-9B-AWQ \
    --trust-remote-code \
    --enforce-eager \
    --gpu-memory-utilization 0.82 \
    --max-model-len 32768 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml
```

Key observations that drive the chart design:

| docker flag | Kubernetes equivalent |
|---|---|
| `--privileged` | `securityContext.privileged: true` |
| `--ipc=host` | `hostIPC: true` in pod spec |
| `-v <host-path>:/root/.cache/huggingface` | PVC mounted at `/root/.cache/huggingface` |
| First positional arg (model path) | `args[0]` in container spec |
| `-p 8000:8000` | container port `8000`, NodePort service |

## Architecture

- One `Deployment` per model → one Pod per model
- One `Service` (NodePort) per model
- All pods share the same PVC mounted at `/root/.cache/huggingface`
- Each model runs a single `vllm/vllm-openai` container
- Model path is the **first positional arg** to the container (not `--model=`)

## values.yaml Changes

Replace the existing `service`, `livenessProbe`, `readinessProbe`, `volumes`, and `volumeMounts` sections with a `models` list and `pvc` config:

```yaml
image:
  repository: vllm/vllm-openai
  tag: "v0.18.0"
  pullPolicy: IfNotPresent

# PVC mounted at /root/.cache/huggingface in every model pod
pvc:
  existingClaim: ai-models-storage-pvc

models:
  - name: Qwen3.5-9B-AWQ
    # Path inside the container (= inside the PVC mount at /root/.cache/huggingface)
    path: /root/.cache/huggingface/Qwen3.5-9B-AWQ
    nodePort: 30800
    vllm:
      gpuMemoryUtilization: 0.82
      maxModelLen: 32768
      trustRemoteCode: true
      enforceEager: true
      enableAutoToolChoice: true
      toolCallParser: qwen3_xml

  - name: mistral-7b
    path: /root/.cache/huggingface/mistral-7b
    nodePort: 30801
    vllm:
      gpuMemoryUtilization: 0.8
      maxModelLen: 4096
      trustRemoteCode: false
      enforceEager: false
      enableAutoToolChoice: false
      toolCallParser: ""

# Shared settings applied to all model pods
podAnnotations: {}
podLabels: {}
nodeSelector: {}
tolerations: []
affinity: {}

serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

resources:
  limits:
    nvidia.com/gpu: 1
```

### Model field reference

| Field | Required | Description |
|---|---|---|
| `name` | yes | Resource name suffix (`vllm-<name>`) and `--served-model-name` |
| `path` | yes | Full container path to the model dir (inside `/root/.cache/huggingface`) |
| `nodePort` | yes | NodePort number (cluster range, typically 30000–32767) |
| `vllm.gpuMemoryUtilization` | no | Fraction of GPU memory (e.g. `0.82`) |
| `vllm.maxModelLen` | no | Max token context length |
| `vllm.trustRemoteCode` | no | Pass `--trust-remote-code` |
| `vllm.enforceEager` | no | Pass `--enforce-eager` |
| `vllm.enableAutoToolChoice` | no | Pass `--enable-auto-tool-choice` |
| `vllm.toolCallParser` | no | Pass `--tool-call-parser <value>` if non-empty |
| `nodeSelector` | no | Node selector for this model's pod; overrides global `nodeSelector` |

## Template Changes

### 1. templates/deployment.yaml

```yaml
{{- range .Values.models }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "vllm.fullname" $ }}-{{ .name }}
  labels:
    {{- include "vllm.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "vllm.selectorLabels" $ | nindent 6 }}
      app.kubernetes.io/component: {{ .name }}
  template:
    metadata:
      {{- with $.Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "vllm.labels" $ | nindent 8 }}
        app.kubernetes.io/component: {{ .name }}
        {{- with $.Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      hostIPC: true
      serviceAccountName: {{ include "vllm.serviceAccountName" $ }}
      containers:
        - name: vllm
          image: "{{ $.Values.image.repository }}:{{ $.Values.image.tag | default $.Chart.AppVersion }}"
          imagePullPolicy: {{ $.Values.image.pullPolicy }}
          securityContext:
            privileged: true
          args:
            - {{ .path }}
            - --served-model-name={{ .name }}
            - --port=8000
            {{- with .vllm }}
            {{- if .gpuMemoryUtilization }}
            - --gpu-memory-utilization={{ .gpuMemoryUtilization }}
            {{- end }}
            {{- if .maxModelLen }}
            - --max-model-len={{ .maxModelLen | toString }}
            {{- end }}
            {{- if .trustRemoteCode }}
            - --trust-remote-code
            {{- end }}
            {{- if .enforceEager }}
            - --enforce-eager
            {{- end }}
            {{- if .enableAutoToolChoice }}
            - --enable-auto-tool-choice
            {{- end }}
            {{- if .toolCallParser }}
            - --tool-call-parser={{ .toolCallParser }}
            {{- end }}
            {{- end }}
          ports:
            - name: http
              containerPort: 8000
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 60
            periodSeconds: 10
          resources:
            {{- toYaml $.Values.resources | nindent 12 }}
          volumeMounts:
            - name: hf-cache
              mountPath: /root/.cache/huggingface
      volumes:
        - name: hf-cache
          persistentVolumeClaim:
            claimName: {{ $.Values.pvc.existingClaim }}
      {{- with $.Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $.Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $.Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
```

### 2. templates/service.yaml

```yaml
{{- range .Values.models }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "vllm.fullname" $ }}-{{ .name }}
  labels:
    {{- include "vllm.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
spec:
  type: NodePort
  ports:
    - port: 8000
      targetPort: http
      protocol: TCP
      name: http
      nodePort: {{ .nodePort }}
  selector:
    {{- include "vllm.selectorLabels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
{{- end }}
```

### 3. templates/NOTES.txt

```
vLLM deployed with {{ len .Values.models }} model(s):

{{- range .Values.models }}
  {{ .name }}
    Path:     {{ .path }}
    NodePort: {{ .nodePort }}
    URL:      http://<NODE_IP>:{{ .nodePort }}/v1
{{- end }}

Get a node IP:
  kubectl get nodes -o wide

Test a model:
  curl http://<NODE_IP>:<nodePort>/v1/models
```

### 4. Remove unused templates

- `templates/ingress.yaml` — not needed for NodePort
- `templates/hpa.yaml` — not applicable
- `templates/tests/test-connection.yaml` — remove or replace

## Implementation Steps

1. Rewrite `values.yaml` with the new structure above
2. Rewrite `templates/deployment.yaml` with the range loop
3. Rewrite `templates/service.yaml` with the range loop
4. Update `templates/NOTES.txt`
5. Delete `templates/ingress.yaml`, `templates/hpa.yaml`
6. Bump `Chart.yaml` version to `0.2.0`, set `appVersion` to `v0.18.0`

## Testing Checklist

- [ ] `helm template` renders one Deployment and one Service per model with no errors
- [ ] Pod starts with `hostIPC: true` and `privileged: true`
- [ ] PVC is mounted at `/root/.cache/huggingface` in each pod
- [ ] Model path arg resolves to the correct directory inside the container
- [ ] Each pod passes `/health` readiness probe before receiving traffic
- [ ] `curl http://<NODE_IP>:<nodePort>/v1/models` returns the correct `--served-model-name`
- [ ] GPU is allocated (`nvidia.com/gpu: 1` per pod)
