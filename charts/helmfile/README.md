# Helmfile for K8s deployments

This directory contains a [Helmfile](https://github.com/helmfile/helmfile) that deploys all Helm charts currently in use on the cluster, using the local charts in `../`.

## Excluded releases (do not add)

The following are **not** in the Helmfile because they are created and managed automatically:

- `fleet-agent-c-5wxxn`
- `rancher-monitoring-crd`
- `rancher-webhook`

Releases not in the catalog (no local chart) are also excluded: `docker-fs-search`, `quarm-charm-calculator`, `sd`.

## Install order (dependency layers)

Releases are ordered so that infrastructure and networking are installed before applications:

1. **Layer 0 – Infrastructure:** cert-manager, ceph-csi, descheduler, gpu-operator, metallb  
2. **Layer 1 – Networking:** nginx-ingress-wes, cloudflare-dns-proxy, generic-ingress-*, opensprinkler  
3. **Layer 2 – Observability:** kube-prometheus-stack, kuberhealthy, tesla-wall-connector  
4. **Layer 3 – Applications:** all remaining releases  

`needs:` is used so that ingress-related releases wait on cert-manager, and oauth2-proxy waits on authentik.

## Prerequisites

- [helmfile](https://github.com/helmfile/helmfile) installed  
- `kubectl` context set to the target cluster  
- Helm 3  

## Commands

From this directory (`rancher-catalog/charts/helmfile/`):

```bash
# Normal workflow: diff and apply without managing chart dependencies.
# Uses each chart as-is (committed charts/ and Chart.lock). Respects release ordering (needs:).
helmfile diff --skip-deps
helmfile apply --skip-deps
```

### Per-chart diff (e.g. from chart dir)

When running `helm diff upgrade` from a chart directory (e.g. `gitea-wes`), use **`--reset-values`** so the diff uses the chart's `values.yaml` instead of reusing the last release's values. Otherwise the "new" manifest can match the old one and image/value overrides in the chart won't show.

```bash
cd ../gitea-wes
helm diff upgrade gitea . -n gitea --reset-values --context 20
```

- **`--reset-values`** – build the "new" side from the chart's defaults only (so bitnamilegacy and other chart overrides appear in the diff).
- **`--context 20`** (`-C 20`) – show 20 lines of context around each change (default can hide distant changes).
```

**Why `--skip-deps`:** Helmfile would otherwise run `helm dependency build` for every local chart and require all Chart.yaml repo URLs to be in `repositories:` and reachable. We use helmfile only to version-control the list of releases and deployment order; chart dependencies are built manually in each chart and committed.

When you add or change a chart’s dependencies (Chart.yaml), build and commit them:

```bash
# Option A: in the chart directory
cd ../some-chart-wes && helm dep up && git add charts/ Chart.lock && git commit

# Option B: let helmfile do it once (after adding any new repo to helmfile.yaml)
helmfile repos
helmfile deps
```

## Values

Each release has a values file under `values/<release-name>.yaml`; these are merged over each chart’s default `values.yaml`. To use only values stored inside each chart, remove the `values:` entry for that release in `helmfile.yaml`. To backfill from the cluster:

```bash
helm get values RELEASE_NAME -n NAMESPACE > values/RELEASE_NAME.yaml
```
