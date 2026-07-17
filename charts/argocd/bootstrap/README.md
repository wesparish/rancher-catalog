# Bootstrapping ArgoCD

The one manual step needed after a fresh k3s install (or any time ArgoCD itself needs to be
(re)installed) — everything after this is managed by ArgoCD itself from git.

```bash
kubectl create namespace argocd
helm repo add argo-helm https://argoproj.github.io/argo-helm
helm install argocd argo-helm/argo-cd -n argocd
```

Then apply the three control resources in this directory's parent (`argocd/`):

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/storage-app.yaml
kubectl apply -f argocd/applicationset.yaml
```

`storage-app.yaml` is applied separately (and syncs at wave "-1", before everything else) since
it's a single hand-written `Application`, not one of the generated ones — it points at
`charts/storage/`'s static PV/PVC manifests as plain YAML, not a Helm chart. Sync it first and
confirm every PVC is `Bound` before syncing anything else, or charts referencing an
`existingClaim` will hang waiting on an unbound PVC.

From here, ArgoCD reconciles everything in `argocd/applicationset.yaml`'s list — one `Application`
per release, in the sync-wave order recorded there (0=infra, 1=networking, 2=observability,
3=applications). Nothing syncs automatically; every `Application` starts manual-sync-only. Review
each one's diff before syncing, same as the dry-run pass documented in
`docs/2026-07-15-argocd-dry-run-checklist.md`.

## Not yet part of this bootstrap

- **wes-chat** — deliberately excluded (separate repo, throwaway test app). See the dry-run
  checklist's "Excluded" section.
- **keycloak** — deprecated, uninstalled, deliberately excluded.
