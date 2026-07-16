# Bootstrapping ArgoCD

The one manual step needed after a fresh k3s install (or any time ArgoCD itself needs to be
(re)installed) — everything after this is managed by ArgoCD itself from git.

```bash
kubectl create namespace argocd
helm repo add argo-helm https://argoproj.github.io/argo-helm
helm install argocd argo-helm/argo-cd -n argocd
```

Then apply the two control resources in this directory's parent (`argocd/`):

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml
```

From here, ArgoCD reconciles everything in `argocd/applicationset.yaml`'s list — one `Application`
per release, in the sync-wave order recorded there (0=infra, 1=networking, 2=observability,
3=applications). Nothing syncs automatically; every `Application` starts manual-sync-only. Review
each one's diff before syncing, same as the dry-run pass documented in
`docs/2026-07-15-argocd-dry-run-checklist.md`.

## Not yet part of this bootstrap

- **Static storage (PVs/PVCs)** — currently tracked separately in the `rancher-volumes` repo,
  applied manually. Not yet folded into this repo or wired into ArgoCD. On a full wipe, these
  need to be reapplied (`kubectl apply -f` the manifests in that repo) *before* syncing any
  `Application` that references an `existingClaim`, or those pods will hang waiting on an unbound
  PVC.
- **wes-chat** — deliberately excluded (separate repo, throwaway test app). See the dry-run
  checklist's "Excluded" section.
- **keycloak** — deprecated, uninstalled, deliberately excluded.
