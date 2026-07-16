# ArgoCD Transition Dry-Run Checklist

Step 1 of the ArgoCD transition plan: for every live Helm release, render its chart with the
committed `values.yaml` and diff the result against what's actually running — with nothing
applied. This is the "does everything already match" check before any ArgoCD infrastructure
gets built.

**Method:** `helm template <release> <chart> -n <namespace> -f <chart>/values.yaml --no-hooks
--api-versions networking.k8s.io/v1/Ingress --api-versions discovery.k8s.io/v1/EndpointSlice`
piped into `kubectl diff -f - -n <namespace>`. `--no-hooks` excludes `helm test` pods (they never
exist live, so including them makes every chart look "different"). Both `--api-versions` entries
resolve `.Capabilities.APIVersions.Has "..."` conditionals correctly — without them, charts that
branch on cluster capabilities render their old/fallback path purely as an artifact of offline
rendering, not a real bug (this cost a full false-positive pass each on the Ingress API and the
`discovery.k8s.io/v1/EndpointSlice` check — cheaper to just always pass both). `-n` is required
per-release except `cert-manager` and `kube-prometheus-stack`, which legitimately create resources
in `kube-system` by upstream chart design.

**Read `kubectl diff` output carefully — `---`/`+++` direction is easy to invert.** `---` is
always LIVE (current cluster state), `+++` is always MERGED (what the chart would change it to);
a `-` line is being removed (i.e. it's the live value), a `+` line is being added (i.e. it's the
chart's value). Got this backwards three separate times during the 2026-07-15 follow-up pass
(borg-wes, gpu-operator, rocketchat) before catching each one via a direct `kubectl get`
cross-check. **Don't trust the diff text alone for anything you're about to act on — verify the
live value with a plain `kubectl get -o jsonpath` first.**

**`helm upgrade` does not self-heal drift.** It diffs the *previous recorded release's* rendered
manifest against the *new* one — not live state. If a value hasn't changed in the chart since the
last release, Helm treats it as "nothing to do" even if live has drifted from both (found this
with rocketchat's `managed-by` label — `helm upgrade` reported success but silently left the
label untouched; had to `kubectl label --overwrite` directly). This is exactly the class of gap
ArgoCD's continuous live-state reconciliation is meant to close.

44 live releases checked (of 51 total — excluded `fleet-agent` ×2, `rancher-monitoring-crd`,
`rancher-webhook` as Rancher-auto-managed, and `docker-fs-search`/`quarm-charm-calculator`/`sd`
as already-known not-in-catalog, per the existing `helmfile.yaml` notes).

## Do not sync these as-is

Four releases would cause a real incident if synced blindly (via ArgoCD or `helm upgrade`),
independent of anything ArgoCD-specific:

| Release | What would happen | Why |
|---|---|---|
| **jitsi** | ~~Rotates `JICOFO_AUTH_PASSWORD`, `JICOFO_COMPONENT_SECRET`, `JVB_AUTH_PASSWORD`~~ **Fixed 2026-07-15.** | These secrets live in the vendored `jitsi-meet` subchart (`charts/jitsi-meet/templates/{jicofo,jvb}/xmpp-secret.yaml`), not jitsi-wes's own templates — patched the same `lookup`-based fix in directly. One extra wrinkle found here: this chart had **both** an unpacked `charts/jitsi-meet/` directory and `charts/jitsi-meet-1.5.1.tgz` — Helm uses the unpacked directory when both exist, so the tgz alone isn't enough; both were patched and verified in sync. Verified via `helm template --dry-run=server`: both secrets now match live exactly and are stable across repeated renders. See `jitsi-wes/README.md` — this patch will be silently lost if the `jitsi-meet` dependency is ever regenerated (`helm dependency update`/`build`), so it documents how to reapply it. |
| ~~keycloak~~ | ~~Rotates the Redis sidecar's `redis-password`~~ | **Update (2026-07-15): no longer applicable.** Keycloak is being deprecated (no longer used) — excluded from the ArgoCD migration rather than fixed. See "Deprecated releases" below. |
| **onlyoffice** | ~~Rotates `jwt-secret`~~ **Fixed 2026-07-15.** | This is the shared secret OnlyOffice's document server and its client integration (ownCloud) both need — rotating it broke document editing until both sides were reconfigured, which matches a JWT issue seen in the past. `templates/jwt-secret.yaml` now uses `lookup` to reuse the existing Secret's value, only generating fresh randomness on first install. Verified via `helm template --dry-run=server`: the rendered value now matches the live secret exactly and is stable across repeated renders. Note: `helm template` alone (without `--dry-run=server`) can't exercise `lookup` — it always renders empty, so use `--dry-run=server` (or a real `helm upgrade`/ArgoCD sync, which does connect live) to verify this class of fix. |
| **borg-wes** | Would resume the `borg-backup-cephfs-remote` CronJob | Live is `suspend: true`, chart renders `suspend: false`. **Update (2026-07-15): confirmed intentional, not drift** — the remote backup target (`j-dock1.weshouse`) has been unreachable for ~100 days (backups failed 3x in a row ~100-102 days ago, then got suspended; host currently gives "No route to host"). Don't sync/unsuspend until the backup server is back online, or `values.yaml` should be updated to `suspend: true` to match reality |

**Still needs a fix before it's ever synced by ArgoCD:** borg-wes needs `values.yaml` updated to
reflect `suspend: true` to match reality, once confirmed the backup target is genuinely down
long-term (see update above) rather than a transient outage.

## Deprecated releases

| Release | Status |
|---|---|
| **keycloak** | No longer used (2026-07-15). Excluded from the ArgoCD migration going forward — not worth fixing its secret-rotation bug for a chart being retired. Confirmed safe to deprecate: the cluster's real SSO (`oauth2-proxy-wes`) uses Authentik, not Keycloak; Keycloak's own bundled `oauth2-proxy` only protects its own admin UI; `borg-wes`/`duplicacy-wes` only reference `keycloak-data` as a backup path entry, not a functional dependency. **`helm uninstall`'d 2026-07-15.** `keycloak-data` PVC was statically provisioned via `existingClaim` (not chart-owned), so it was untouched by the uninstall — still `Bound` to the same PV, data fully intact if ever needed again. `keycloak-wes` chart directory left in the catalog for now (not deleted) in case it's needed for reference. |

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
| Clean (chart matches live exactly) | 33 |
| Fixed 2026-07-15 (jitsi, onlyoffice, authentik, gpu-operator, rocketchat) | 5 |
| Deprecated 2026-07-15 (keycloak) | 1 |
| Held (mariadb-operator) / needs live sync only, no repo change (node-red) | 2 |
| Chart bug (blocks render/apply) | 2 |
| No chart in catalog | 1 (`wes-chat`) |
| Excluded (Rancher-managed / already known not-in-catalog) | 7 |

Total: 33 + 5 + 1 + 2 + 2 + 1 + 7 = 51, matching all live releases in the cluster.

### Clean — 33

`ark`, `authentik`, `borg-wes`, `ceph-csi`, `cert-manager`, `cloudflare-dns-proxy`, `descheduler`,
`frigate`, `generic-ingress-ceph-dashboard`, `gitea`, `gpu-operator`, `guacamole`,
`home-assistant`, `immich`, `jitsi`, `kube-prometheus-stack`, `kuberhealthy`, `mailu-new`,
`metallb`, `moonlight-web-stream`, `mosquitto`, `nginx-ingress-wes`, `oauth2-proxy`, `omada`,
`onlyoffice`, `opensprinkler`, `owncloud`, `pihole`, `plex`, `rocketchat`, `satisfactory`,
`tandoor`, `tasks-md`, `vaultwarden-wes`, `virt-manager`, `vllm`, `zigbee2mqtt`

*(Several of these — `ark`/`pihole` from the `rancher-volumes`/pihole-v6 passes, and
`authentik`/`borg-wes`/`gpu-operator`/`jitsi`/`kube-prometheus-stack`/`onlyoffice`/`rocketchat`
from this pass — only became clean today; this list reflects current state, not day-one.)*

### Resolved 2026-07-15

- **kube-prometheus-stack** — was a false alarm, not real drift. Same root cause as the Ingress
  issue: another `.Capabilities.APIVersions.Has` conditional (gated on
  `discovery.k8s.io/v1/EndpointSlice`), which the original sweep hadn't passed via
  `--api-versions`. Re-verified with the correct flag: actually clean.
- **authentik** — real bug, not a preference. `bitnami/redis:8.0.1-debian-12-r2` (what was live)
  returned a **404 on Docker Hub — the tag no longer exists**; `bitnamilegacy/redis:8.0.1-debian-12-r2`
  (what the chart already specified) is the one that's actually pullable. The running pod was fine
  on its cached image but would have failed to pull on any future reschedule — a real threat to
  the wipe-and-redeploy goal. Restarted `authentik-redis-master` to pick up the correct image;
  verified healthy afterward (a brief worker reconnect blip resolved itself).
- **gpu-operator** — **initial diff direction was backwards.** Live was actually `replicas: 4`
  (matching all 3 GPU nodes' advertised capacity) the whole time; it was the chart's own
  `time-slicing-configmap.yaml` template that had a stale hardcoded `2`. Caught via direct
  `kubectl get` before applying anything — fixed the chart, never touched live.
- **node-red** — no repo change needed. The chart's `static-config-files/settings.js` already
  says `level: "info"`; it's live that's still running the older `"debug"` value. A normal
  restart/sync will pick up `"info"` automatically whenever convenient.
- **rocketchat** — confirmed intentional: `templates/gotify/` and `templates/push-gateway/`
  deliberately set `managed-by: {{ .Release.Service }}-gotify` / `-pushgateway` to distinguish
  those sub-components; live was on an older revision that predated this. Confirmed nothing
  (ServiceMonitors, NetworkPolicies) selects on the label value. **Worth noting:** `helm upgrade`
  alone did *not* fix this — it diffs the previous chart-rendered manifest against the new one,
  not live state, so it silently skipped these 4 resources since the chart's own desired value
  hadn't changed since the last recorded release. Had to `kubectl label --overwrite` directly.
  This is a concrete example of the exact gap ArgoCD's continuous live-state reconciliation
  would close that plain `helm upgrade` can't.
- **borg-wes** — fixed (see "Do not sync" above).

### Still open — 2

| Release | Status | Recommended action |
|---|---|---|
| **mariadb-operator** | Held, per instruction | `mariadb-test` CR not applied — chart left as documentation for a future homeassistant-db migration |
| **node-red** | No repo change needed | Live will pick up the chart's already-correct `"info"` log level on next restart/sync |

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
4. ~~Fix jitsi's secret regeneration~~ — done 2026-07-15.
5. ~~Fix borg-wes's `values.yaml` `suspend` value~~ — done 2026-07-15, backup target confirmed
   long-term down.
6. ~~Work through the remaining 7 drift items~~ — done 2026-07-15: `authentik`, `gpu-operator`,
   `kube-prometheus-stack`, and `rocketchat` fixed (see "Resolved 2026-07-15" above);
   `mariadb-operator` held per instruction; `node-red` needs no repo change, just a live sync;
   `open-webui` was already benign, no action needed.
7. Once `wes-chat` has a chart (or is explicitly excluded) and `mariadb-operator`/`node-red` are
   settled, re-run this same sweep to confirm it comes back all-clean before building any ArgoCD
   `Application`/`ApplicationSet` resources.
