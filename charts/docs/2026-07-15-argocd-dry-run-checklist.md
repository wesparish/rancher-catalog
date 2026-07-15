# ArgoCD Transition Dry-Run Checklist

Step 1 of the ArgoCD transition plan: for every live Helm release, render its chart with the
committed `values.yaml` and diff the result against what's actually running — with nothing
applied. This is the "does everything already match" check before any ArgoCD infrastructure
gets built.

**Method:** `helm template <release> <chart> -n <namespace> -f <chart>/values.yaml --no-hooks
--api-versions networking.k8s.io/v1/Ingress` piped into `kubectl diff -f - -n <namespace>`.
`--no-hooks` excludes `helm test` pods (they never exist live, so including them makes every
chart look "different"). `--api-versions` resolves a couple of charts' old
`.Capabilities`-based Ingress-version conditionals correctly — without it they render the
removed `extensions/v1beta1` API purely as an artifact of offline rendering, not a real bug.
`-n` is required per-release except `cert-manager` and `kube-prometheus-stack`, which
legitimately create resources in `kube-system` by upstream chart design.

44 live releases checked (of 51 total — excluded `fleet-agent` ×2, `rancher-monitoring-crd`,
`rancher-webhook` as Rancher-auto-managed, and `docker-fs-search`/`quarm-charm-calculator`/`sd`
as already-known not-in-catalog, per the existing `helmfile.yaml` notes).

## Do not sync these as-is

Four releases would cause a real incident if synced blindly (via ArgoCD or `helm upgrade`),
independent of anything ArgoCD-specific:

| Release | What would happen | Why |
|---|---|---|
| **jitsi** | Rotates `JICOFO_AUTH_PASSWORD`, `JICOFO_COMPONENT_SECRET`, `JVB_AUTH_PASSWORD` | Chart generates these with `randAlphaNum`-style functions with no `lookup` against the existing Secret — confirmed by rendering twice and diffing: values differ between the two renders, not just against live. **Not yet fixed.** |
| ~~keycloak~~ | ~~Rotates the Redis sidecar's `redis-password`~~ | **Update (2026-07-15): no longer applicable.** Keycloak is being deprecated (no longer used) — excluded from the ArgoCD migration rather than fixed. See "Deprecated releases" below. |
| **onlyoffice** | ~~Rotates `jwt-secret`~~ **Fixed 2026-07-15.** | This is the shared secret OnlyOffice's document server and its client integration (ownCloud) both need — rotating it broke document editing until both sides were reconfigured, which matches a JWT issue seen in the past. `templates/jwt-secret.yaml` now uses `lookup` to reuse the existing Secret's value, only generating fresh randomness on first install. Verified via `helm template --dry-run=server`: the rendered value now matches the live secret exactly and is stable across repeated renders. Note: `helm template` alone (without `--dry-run=server`) can't exercise `lookup` — it always renders empty, so use `--dry-run=server` (or a real `helm upgrade`/ArgoCD sync, which does connect live) to verify this class of fix. |
| **borg-wes** | Would resume the `borg-backup-cephfs-remote` CronJob | Live is `suspend: true`, chart renders `suspend: false`. **Update (2026-07-15): confirmed intentional, not drift** — the remote backup target (`j-dock1.weshouse`) has been unreachable for ~100 days (backups failed 3x in a row ~100-102 days ago, then got suspended; host currently gives "No route to host"). Don't sync/unsuspend until the backup server is back online, or `values.yaml` should be updated to `suspend: true` to match reality |

**Still needs a fix before it's ever synced by ArgoCD:** jitsi's secret templates need the same
`lookup`-based fix applied to onlyoffice's. borg-wes just needs `values.yaml` updated to reflect
`suspend: true` to match reality, once confirmed the backup target is genuinely down long-term
(see update above) rather than a transient outage.

## Deprecated releases

| Release | Status |
|---|---|
| **keycloak** | No longer used (2026-07-15). Excluded from the ArgoCD migration going forward — not worth fixing its secret-rotation bug for a chart being retired. Confirmed safe to deprecate: the cluster's real SSO (`oauth2-proxy-wes`) uses Authentik, not Keycloak; Keycloak's own bundled `oauth2-proxy` only protects its own admin UI; `borg-wes`/`duplicacy-wes` only reference `keycloak-data` as a backup path entry, not a functional dependency. Live teardown (helm uninstall / PV cleanup) not yet done — pending a decision on timing. |

## Two unrelated chart bugs surfaced

Not an ArgoCD issue — these would fail on a plain `helm upgrade` today, right now, regardless of
this migration:

| Chart | Bug | Where |
|---|---|---|
| **generic-ingress** (used by `generic-ingress-rancherserver`) | `values.yaml` sets `name: HeaterMeter` — capital letters aren't valid in a Kubernetes object name (DNS-1035) | `generic-ingress/values.yaml:1` |
| **tesla-wall-connector-exporter-wes** | Service `type: externalName` — Kubernetes requires `ExternalName` (capital N) | `tesla-wall-connector-exporter-wes/templates/service.yaml:9` |

## Summary

| Status | Count |
|---|---|
| Clean (chart matches live exactly) | 30 |
| Fixed 2026-07-15 (onlyoffice) | 1 |
| Deprecated 2026-07-15 (keycloak) | 1 |
| Drift remaining (needs a decision) | 9 |
| Chart bug (blocks render/apply) | 2 |
| No chart in catalog | 1 (`wes-chat`) |
| Excluded (Rancher-managed / already known not-in-catalog) | 7 |

Total: 30 + 1 + 1 + 9 + 2 + 1 + 7 = 51, matching all live releases in the cluster.

### Clean — 30

`ark`, `ceph-csi`, `cert-manager`, `cloudflare-dns-proxy`, `descheduler`, `frigate`,
`generic-ingress-ceph-dashboard`, `gitea`, `guacamole`, `home-assistant`, `immich`, `kuberhealthy`,
`mailu-new`, `metallb`, `moonlight-web-stream`, `mosquitto`, `nginx-ingress-wes`, `oauth2-proxy`,
`omada`, `opensprinkler`, `owncloud`, `pihole`, `plex`, `satisfactory`, `tandoor`, `tasks-md`,
`vaultwarden-wes`, `virt-manager`, `vllm`, `zigbee2mqtt`

*(A few of these, like `ark` and `pihole`, only became clean after fixes made in the
`rancher-volumes` pass and the pihole v6 migration earlier this week; this list reflects current
state, not day-one state.)*

### Drift — 9 remaining (needs a decision, not necessarily a fix)

| Release | Diff | Recommended action |
|---|---|---|
| **jitsi** | Non-deterministic secrets (see above) | Fix chart before syncing — see "Do not sync" |
| **borg-wes** | `suspend: false` (chart) vs. `true` (live) | Fix `values.yaml` before syncing — see "Do not sync" |
| **authentik** | Redis image `bitnamilegacy/redis` (chart) vs. `bitnami/redis` (live) | Real drift — decide which is correct and update the losing side. Bitnami moved free-tier images to `bitnamilegacy/*` in 2025; likely the chart is right and live predates the switch, but confirm before assuming |
| **gpu-operator** | `time-slicing-config` replicas: `4` (chart) vs. `2` (live) | Someone tuned this live. Decide which is the real intended setting and update `values.yaml` to match |
| **kube-prometheus-stack** | Live `ClusterRole` has extra `endpointslices` RBAC permissions the chart doesn't grant | Check whether a newer chart/operator version needs this permission — may indicate the deployed chart version is behind what's actually running |
| **mariadb-operator** | Chart would create a new `mariadb-test` MariaDB CR (`database: homeassistant-db`) that doesn't exist live yet | Not a bug — this is the not-yet-applied example resource from the chart's own README. Decide whether to apply it or hold |
| **node-red** | Log level `debug` (chart) vs. `info` (live) | Low-risk. Update `values.yaml` to match live, or decide `debug` should ship |
| **open-webui** | Live has `kubectl.kubernetes.io/restartedAt` annotation, chart doesn't | Benign — this is just a marker left by a manual `kubectl rollout restart`. Safe to sync away |
| **rocketchat** | Live labels 2 Deployments + 2 Services `app.kubernetes.io/managed-by: Helm-gotify` / `Helm-pushgateway`; chart renders plain `Helm` | Cosmetic. Confirm nothing depends on the custom label value before letting a sync overwrite it |

## Not checked

- **wes-chat** (namespace `wchat`) — live and active, but has no chart anywhere in this catalog.
  Needs a chart written before it can be part of the ArgoCD (or even Helmfile) setup at all.
- **immich-typesense-data** PV — flagged in the `rancher-volumes` pass as tracked-but-not-live,
  still an open decision, unrelated to this chart-diff pass.

## Next steps

1. Fix the two real chart bugs (`generic-ingress` HeaterMeter naming, `tesla-wall-connector`
   externalName casing) — independent of ArgoCD, these block any future `helm upgrade` too.
2. ~~Fix onlyoffice's jwt-secret regeneration~~ — done 2026-07-15.
3. ~~Decide keycloak's fate~~ — deprecated 2026-07-15, excluded from migration.
4. Apply the same `lookup`-based fix to jitsi's secrets, and fix borg-wes's `values.yaml`
   `suspend` value (pending confirmation the backup target outage is long-term).
5. Work through the remaining 7 drift items (`authentik`, `gpu-operator`, `kube-prometheus-stack`,
   `mariadb-operator`, `node-red`, `open-webui`, `rocketchat`) — each is a real, small decision
   (which value should win), not a bug.
6. Once everything above is either fixed or an explicit "chart is correct, ignore this" call has
   been made, re-run this same sweep — it should come back all-clean (or with intentional,
   understood diffs only) before building any ArgoCD `Application`/`ApplicationSet` resources.
