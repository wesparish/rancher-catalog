# docs

Working notes for this repo's infrastructure — chart upgrades and the ongoing move to ArgoCD.

- [`2026-07-06-helm-chart-version-audit.md`](2026-07-06-helm-chart-version-audit.md) — audit of
  every deployed chart's current version against upstream latest, with per-chart upgrade notes
  (what changed, what broke, how it was verified). A couple of entries are marked won't-upgrade
  with the reason recorded (a host-level NVIDIA driver dependency, an upstream Docker entrypoint
  change with no config escape hatch).
- [`2026-07-15-argocd-dry-run-checklist.md`](2026-07-15-argocd-dry-run-checklist.md) — the
  pre-migration validation pass: render every chart's committed `values.yaml` and diff it against
  what's actually live, with nothing applied, before trusting ArgoCD (or anything else) to sync
  it. Found and fixed several real bugs this way — three charts silently rotating secrets on
  every upgrade, a suspended backup job that would have been silently resumed, two charts with
  invalid Kubernetes object names that would fail any future `helm upgrade`. Also documents two
  reusable gotchas: `kubectl diff`'s `---`/`+++` direction is easy to invert, and `helm upgrade`
  does not self-heal drift (it diffs the previous release against the new one, not live state) —
  worth rereading before doing this kind of pass again.

## Current infrastructure direction

Moving off Rancher Manager to bare k3s, and off the ad-hoc `helm upgrade`/`helmfile` workflow
(`../helmfile/`, superseded) onto ArgoCD (`../argocd/`) for continuous, self-healing GitOps. The
goal: be able to wipe the cluster and redeploy everything back to its current state from git,
keeping the underlying persistent data (currently tracked in the separate `rancher-volumes` repo,
not yet folded into this one).

The dry-run checklist above is why `../argocd/applicationset.yaml` could be built with reasonable
confidence that each `Application` will come up clean on first sync — every chart in it was
individually verified against live before being added to the list.
