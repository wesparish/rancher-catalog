# storage

Static `PersistentVolume`/`PersistentVolumeClaim` pairs for every app's data, one file per app
(occasionally split across multiple files when an app has several distinct volumes — see `plex-*`,
`owncloud-*`, `rocketchat-*`).

Moved here 2026-07-16 from a separate `rancher-volumes` repo (`~/workspace/rancher-volumes`) that
was never meant to be its own repo — it just ended up in a different folder a long time ago. This
directory is now the source of truth; the old location has been archived, not deleted (see its
`DO_NOT_USE/README.md`).

## Why these are static, not chart-templated

Every volume is provisioned via the Ceph CSI driver's static-provisioning mode
(`staticVolume: "true"`, a fixed `rootPath` on the CephFS backend, `persistentVolumeReclaimPolicy:
Retain`). This means the underlying data survives independently of whatever consumes it — a chart
can be deleted and reinstalled, a PVC can be deleted and recreated pointing at the same `PV`, and
the data on the Ceph backend is untouched either way. This is the actual mechanism behind the
"wipe the cluster and redeploy, keep the data" goal: reapply these manifests (they don't depend on
anything else existing yet) before syncing any chart that references one via `existingClaim`.

## Adding a new one

Copy `template.yaml`, replace the `<app>`/`<namespace>` placeholders, and pick a `rootPath` that
doesn't collide with an existing one (`grep -h rootPath *.yaml` to check). Match the existing
`accessModes`/capacity conventions loosely based on similar apps — there's no hard rule, just
avoid asking for far more than the app needs.

## Pruning

If an app is decommissioned, remove its git-tracked file here (`git rm`) but leave the live
`PV`/`PVC` and underlying Ceph data alone unless you're certain it's disposable — matches how
several now-undeployed apps were handled during the 2026-07 ArgoCD migration prep (their charts
were removed from tracking, but their storage was left bound and retained). If a volume is
confirmed no longer live at all, comment the file out rather than deleting it outright (see
`immich-typesense.yaml` for the pattern) — keeps the historical rootPath discoverable if the data
is ever needed again.
