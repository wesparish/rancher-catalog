# argocd

GitOps control resources for this repo's ArgoCD deployment. See
[`bootstrap/README.md`](bootstrap/README.md) for one-time setup — installing ArgoCD itself, and
the two different procedures for transitioning the current cluster versus bootstrapping a fresh
one.

- `project.yaml` — the one `AppProject`, scoping this repo as the allowed source.
- `applicationset.yaml` — one `Application` per release, generated from an inline list (name,
  namespace, chart path, sync-wave). This is the file to edit when adding, removing, or
  re-pointing a release — same role `helmfile.yaml`'s `releases:` list used to serve.
- `storage-app.yaml` — a separate, hand-written `Application` for `charts/storage/`'s static
  PV/PVC manifests, synced at wave `-1` (before everything else).

## Local development

Iterating on a chart and want to see it running before committing? `argocd app sync --local`
renders manifests from your local filesystem instead of fetching from git, for one sync only —
nothing is committed or pushed, and the Application's stored source (still pointing at GitHub) is
unaffected, so the next normal sync goes back to using git as usual.

```bash
argocd login <your-argocd-server>       # once per session, if not already logged in

argocd app manifests pihole --local charts/pihole   # just render, don't touch the cluster
argocd app diff pihole --local charts/pihole        # preview what would change
argocd app sync pihole --local charts/pihole        # apply your local changes
```

Replace `pihole`/`charts/pihole` with the Application name and chart path you're working on — same
values as the corresponding entry in `applicationset.yaml`.

Notes:

- This needs the `argocd` CLI logged into the ArgoCD API server — `kubectl` access alone isn't
  enough.
- None of the `Application`s in this repo have `syncPolicy.automated` set, so there's no self-heal
  fighting your local sync. If an app's ever flipped to automated sync while you're actively
  iterating on it, expect ArgoCD to notice the drift from git on its next reconcile loop
  (~3 min) and silently revert your local changes back.
- Once you're happy with a change, commit and push it normally — `--local` is for the iteration
  loop, not a substitute for actually landing the change in git. A change that only exists via
  `--local` sync doesn't survive the next sync (manual or automated) from anyone else, and
  wouldn't be there after a wipe/redeploy.
