# metallb-wes

Wrapper around the [official MetalLB Helm chart](https://artifacthub.io/packages/helm/metallb/metallb) (v0.15.3). Address pools are defined in `values.yaml` and rendered as IPAddressPool + L2Advertisement CRs.

## Force-remove a broken release (e.g. old Bitnami / PSP error)

If `helm uninstall metallb -n metallb` fails (e.g. "no matches for kind PodSecurityPolicy" or "failed to delete release"), the release secret is still pointing at removed APIs. Remove the release from Helm’s view, then delete the namespace (or leave it and install into it):

```bash
# List release secrets for metallb
kubectl get secrets -n metallb -l 'owner=helm' -o name

# Delete every metallb release secret (e.g. sh.helm.release.v1.metallb.v1, .v2, …)
kubectl get secrets -n metallb -o name | grep 'sh\.helm\.release\.v1\.metallb\.' | xargs -r kubectl delete -n metallb

# Optional: remove the namespace and everything in it (LoadBalancer IPs will drop)
kubectl delete namespace metallb

# Recreate namespace and install (if you deleted it)
kubectl create namespace metallb
```

Then install CRDs if needed and run `helm -n metallb install metallb .` (see below).

## CRD management

CRDs are installed by the chart by default (`metallb.crds.enabled: true` in `values.yaml`). The chart installs them as part of the release.

The validation webhook uses `failurePolicy: Ignore` by default so that TLS/cert errors (e.g. webhook cert not ready on first install) do not block creating IPAddressPool/L2Advertisement. You can set `metallb.crds.validationFailurePolicy: Fail` for strict validation once the webhook certificate is stable.

## Manual CRD install (fallback)

If you disabled CRDs (`metallb.crds.enabled: false`) or hit **"ensure CRDs are installed first"**, re-enable CRD management in `values.yaml` (default) and run install/upgrade again. The chart will install CRDs as part of the release.

IPAddressPool and L2Advertisement are rendered by the wrapper chart and applied with the rest of the release.

## Speaker pods not scheduling ("didn't have free ports")

The MetalLB speaker runs with `hostNetwork: true` and binds host ports (memberlist **7946**, metrics **7472**, FRR metrics **7473**). Only one process per node can use those ports. If you see **FailedScheduling** and "didn't have free ports for the requested pod ports":

1. **Leftover speaker pods** – Old MetalLB/Bitnami speaker pods may still be running and holding the ports. List and remove them:

   ```bash
   kubectl get daemonsets,pods -n metallb -o wide
   kubectl get pods -A -o wide | grep -E 'speaker|metallb'
   ```

   If you see a second DaemonSet or old speaker pods not managed by the current release, delete the old DaemonSet (or scale it to 0) so the new speaker can bind the ports:

   ```bash
   kubectl delete daemonset -n metallb <old-speaker-daemonset-name>
   ```

2. **Something else using the ports** – On the affected node(s), check what is using 7946, 7472, 7473 (e.g. another `hostNetwork` pod or a process on the host). Reschedule or stop that workload, or run the speaker on a subset of nodes via `metallb.speaker.nodeSelector` / tolerations so it avoids that node.

## Dependency

Run from the chart directory:

```bash
helm dependency update
```

This fetches the official MetalLB chart into `charts/metallb/`.
