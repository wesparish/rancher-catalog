# Bootstrapping ArgoCD

ArgoCD isn't installed yet. Two different starting points, two different procedures — the current
cluster already has everything running and just needs ArgoCD to *adopt* it; a fresh cluster has
nothing, and needs everything actually created in the right order.

Both start the same way:

```bash
kubectl create namespace argocd
helm repo add argo-helm https://argoproj.github.io/argo-helm
helm install argocd argo-helm/argo-cd -n argocd

kubectl apply -f argocd/project.yaml
```

## Transitioning the current (already-running) cluster

Every release in `argocd/applicationset.yaml` was individually verified against live in
`docs/2026-07-15-argocd-dry-run-checklist.md` — rendered, diffed, and either confirmed clean or
brought into a known/accepted state. That verification is what makes this an *adoption*, not a
redeploy: ArgoCD doesn't use `helm install`/`helm upgrade` under the hood, it renders each chart
and applies the resulting manifests directly (same as Kustomize or plain YAML) — so if the
rendered manifest already matches what's running, nothing gets deleted or recreated. Kubernetes
doesn't care which tool last touched a resource.

1. Apply `storage-app.yaml`:

   ```bash
   kubectl apply -f argocd/storage-app.yaml
   ```

   Every PV/PVC in `charts/storage/` already exists and is `Bound` live, so this should sync as a
   pure no-op — confirm via `argocd app diff storage` before syncing (should be empty), then sync
   and confirm nothing's status changed (`kubectl get pv,pvc -A` — still `Bound`, same names).

2. Apply the `ApplicationSet`:

   ```bash
   kubectl apply -f argocd/applicationset.yaml
   ```

   This generates 42 `Application` resources, all unsynced (no `syncPolicy.automated` anywhere).
   Nothing changes on the cluster yet.

3. For each `Application` — order doesn't matter here the way it does for a fresh cluster,
   everything's already running — check its diff first:

   ```bash
   argocd app diff <name>
   ```

   Per the dry-run checklist, this should already be empty for the 41 confirmed-clean releases.
   `mariadb-operator` will show a diff (the unapplied `mariadb-test` CR) — expected, not a
   problem. If anything else shows an unexpected diff, live has drifted since 2026-07-15/16 —
   treat it the same way the checklist did: figure out which side is right before syncing, don't
   assume the chart wins.

4. Sync each `Application` once its diff looks right:

   ```bash
   argocd app sync <name>
   ```

   Should be a no-op apply for the 41 clean ones — ArgoCD adds its own tracking label to the
   resources, nothing else changes, no pod restarts.

5. **The moment an `Application` is synced, stop running `helm upgrade`/`helmfile apply` against
   that release by hand.** Both tools will still work and both think they own the resources — if
   you (or a stale script/habit) runs `helm upgrade` after ArgoCD has adopted a release, whichever
   one applies last wins, and they'll silently fight if run repeatedly. Once everything's synced,
   retire `charts/helmfile/` entirely rather than leaving it around as a temptation.

6. Optional, once confident: the old Helm release history (`sh.helm.release.v1.<name>.v<N>`
   Secrets in each release's namespace) is now stale — ArgoCD doesn't create or update these, so
   `helm list` will keep showing the release at whatever revision it was on the moment ArgoCD took
   over, forever. Not harmful to leave, but can be confusing later. Delete them per-namespace if
   it bothers you; nothing reads them once ArgoCD owns the release.

## Fresh cluster (after a wipe)

Nothing exists yet — order matters here in a way it doesn't for the transition case above.

1. Apply `storage-app.yaml` and **wait for it to fully sync before doing anything else**:

   ```bash
   kubectl apply -f argocd/storage-app.yaml
   argocd app sync storage
   kubectl get pv,pvc -A   # confirm everything is Bound
   ```

   This is the step that actually matters for the "keep the data" goal — it recreates all 47
   PV/PVC pairs pointing at the same Ceph `rootPath`s as before, so each `PersistentVolume` binds
   to the same underlying data. If any PVC comes up `Pending` instead of `Bound`, stop and debug
   before proceeding — every chart below assumes its `existingClaim` is already satisfied.

2. Apply the `ApplicationSet`:

   ```bash
   kubectl apply -f argocd/applicationset.yaml
   ```

   Same as the transition case, this generates 42 unsynced `Application` resources. Unlike the
   transition case, these now have to be synced in wave order — nothing exists yet, so e.g. an
   ingress created before `cert-manager` is up just won't get a certificate until `cert-manager`
   catches up. Each generated `Application` carries a plain `wave` label (`0`-`3`, duplicating the
   `argocd.argoproj.io/sync-wave` annotation ArgoCD itself reads — the CLI's `-l`/`--selector`
   flag matches labels, not annotations, hence the duplicate). Sync by wave, waiting for each wave
   to be healthy before starting the next:

   ```bash
   argocd app sync -l wave=0 && argocd app wait -l wave=0
   argocd app sync -l wave=1 && argocd app wait -l wave=1
   argocd app sync -l wave=2 && argocd app wait -l wave=2
   argocd app sync -l wave=3 && argocd app wait -l wave=3
   ```

   If this is genuinely a full disaster-recovery scenario and manually syncing 4 waves one at a
   time is too slow, it's reasonable to temporarily add `syncPolicy.automated: {}` to the
   `ApplicationSet` template for this one bootstrap and revert to manual afterward — but that's a
   deliberate one-time trade, not the standing default.

## Not yet part of either path

- **wes-chat** — deliberately excluded (separate repo, throwaway test app). See the dry-run
  checklist's "Excluded" section.
- **keycloak** — deprecated, uninstalled, deliberately excluded.
