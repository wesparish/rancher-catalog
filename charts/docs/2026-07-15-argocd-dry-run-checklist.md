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
| **borg-wes** | ~~Would resume the `borg-backup-cephfs-remote` CronJob~~ **Fixed 2026-07-15.** | Live was `suspend: true`, chart rendered `suspend: false` — the remote backup target (`j-dock1.weshouse`) has been unreachable for ~100 days (backups failed 3x in a row ~100-102 days ago, then got suspended; host gave "No route to host"). `values.yaml` updated to `suspend: true` to match reality; re-enable once the backup server is back online. |

All four items in this section are now resolved.

## Deprecated releases

| Release | Status |
|---|---|
| **keycloak** | No longer used (2026-07-15). Excluded from the ArgoCD migration going forward — not worth fixing its secret-rotation bug for a chart being retired. Confirmed safe to deprecate: the cluster's real SSO (`oauth2-proxy-wes`) uses Authentik, not Keycloak; Keycloak's own bundled `oauth2-proxy` only protects its own admin UI; `borg-wes`/`duplicacy-wes` only reference `keycloak-data` as a backup path entry, not a functional dependency. **`helm uninstall`'d 2026-07-15.** `keycloak-data` PVC was statically provisioned via `existingClaim` (not chart-owned), so it was untouched by the uninstall — still `Bound` to the same PV, data fully intact if ever needed again. `keycloak-wes` chart directory left in the catalog for now (not deleted) in case it's needed for reference. |

## Two unrelated chart bugs — fixed 2026-07-16

Not an ArgoCD issue — these would have failed on a plain `helm upgrade`, regardless of this
migration:

| Chart | Bug | Fix |
|---|---|---|
| **generic-ingress** | `values.yaml`/`questions.yml` set `name: HeaterMeter`/`GenericIngress` — capital letters aren't valid in a Kubernetes object name (DNS-1035). Deeper issue: this shared/base chart's checked-in values didn't match either live app that could plausibly use it — the only release deployed directly from it (`generic-ingress-rancherserver`, 2021, never upgraded since) actually fronts a service called `rancher2`, and there's a separate, unrelated live `heatermeter` service this chart was never wired up to at all. | Reset to generic, validly-cased placeholders (`generic-ingress`) with a comment noting it's meant to be wrapped by an umbrella chart, not deployed with its own baked-in config — matching the existing `generic-ingress-ceph-dashboard`/`generic-ingress-opensprinkler` pattern. Added the missing `generic-ingress-rancherserver/` umbrella chart, values reverse-engineered from the live Ingress/Service/Endpoints (`rancher2`, `172.16.1.107:8443`, HTTPS). Verified via `kubectl diff`: renders identical to live. |
| **tesla-wall-connector-exporter-wes** | Service `type: externalName` (invalid casing) with `.Values.service.externalName` left unset — an abandoned mid-experiment to point the Service directly at hardware, never finished or successfully applied (live has always been plain `ClusterIP`, matching `values.yaml`'s `service.type: ClusterIP`). | Reverted to the values-driven `type: {{ .Values.service.type }}` line that was already commented out just above the broken lines. Verified via `kubectl diff`: renders identical to live. |

## Summary

| Status | Count |
|---|---|
| Clean (chart matches live exactly) | 41 |
| Deprecated 2026-07-15 (keycloak) | 1 |
| Include in ArgoCD, not actively used yet (mariadb-operator) | 1 |
| Excluded, test app (`wes-chat`) | 1 |
| Excluded (Rancher-managed / already known not-in-catalog) | 7 |

Total: 41 + 1 + 1 + 1 + 7 = 51, matching all live releases in the cluster.

### Clean — 41

`ark`, `authentik`, `borg-wes`, `ceph-csi`, `cert-manager`, `cloudflare-dns-proxy`, `descheduler`,
`frigate`, `generic-ingress-ceph-dashboard`, `generic-ingress-rancherserver`, `gitea`,
`gpu-operator`, `guacamole`, `home-assistant`, `immich`, `jitsi`, `kube-prometheus-stack`,
`kuberhealthy`, `mailu-new`, `metallb`, `moonlight-web-stream`, `mosquitto`, `nginx-ingress-wes`,
`node-red`, `oauth2-proxy`, `omada`, `onlyoffice`, `opensprinkler`, `open-webui`, `owncloud`,
`pihole`, `plex`, `rocketchat`, `satisfactory`, `tandoor`, `tasks-md`, `tesla-wall-connector`,
`vaultwarden-wes`, `virt-manager`, `vllm`, `zigbee2mqtt`

*(Many of these only became clean over 2026-07-14 through 2026-07-16 — pihole/ark from the
`rancher-volumes`/pihole-v6 passes, and the majority of the rest from this dry-run pass. This list
reflects current state, not day-one.)*

### Resolved 2026-07-15 through 2026-07-16

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
- **node-red** — the ConfigMap fix needed a real `helm upgrade` (unlike rocketchat below, this one
  *did* apply — the static file's content had genuinely changed since the last recorded release,
  so Helm correctly detected a delta). Then restarted the pod, since ConfigMap volume updates
  don't get re-read by a running Node-RED process without a restart. Verified: pod healthy,
  reconnected to Home Assistant/MQTT/Alexa integrations, `kubectl diff` clean.
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
- **generic-ingress** / **tesla-wall-connector-exporter-wes** — fixed (see "Two unrelated chart
  bugs" above).

### mariadb-operator — decision made, not yet a "clean" state

Not actively used for anything yet (no real MariaDB workload has been migrated onto it) — the
`mariadb-test` CR (`database: homeassistant-db`) remains unapplied, chart left as documentation
for a future migration. **Decision 2026-07-16: include it in the ArgoCD app list anyway** — it's a
legitimate deployed chart (the operator itself is running), just without a real consumer yet.
Expect this one to keep showing the `mariadb-test` diff until that migration actually happens or
the example resource is removed from the chart.

## Excluded

- **wes-chat** (namespace `wchat`) — its chart lives in a separate standalone repo
  (`~/workspace/wes-chat`, no `origin` remote configured, single commit) rather than this catalog.
  **Update 2026-07-16: confirmed a throwaway AI-generated test, not something to maintain.**
  Excluded from the ArgoCD migration entirely — no chart needed here. Still live in the cluster
  (left running, per instruction) but untracked; `wchat-data`'s PVC stays as-is in
  `rancher-volumes`.
- **immich-typesense-data** PV — **resolved 2026-07-16.** Confirmed no live typesense pod/PVC
  exists (immich-wes is on v1.91.4, well past upstream dropping Typesense for Postgres pgvector).
  Commented out in `rancher-volumes/immich-typesense.yaml` rather than deleted — the underlying
  Ceph data at its `rootPath` was never removed, in case it's ever needed.

## Next steps

1. ~~Fix the two real chart bugs~~ — done 2026-07-16 (see "Two unrelated chart bugs" above).
2. ~~Fix onlyoffice's jwt-secret regeneration~~ — done 2026-07-15.
3. ~~Decide keycloak's fate~~ — deprecated 2026-07-15, excluded from migration.
4. ~~Fix jitsi's secret regeneration~~ — done 2026-07-15.
5. ~~Fix borg-wes's `values.yaml` `suspend` value~~ — done 2026-07-15, backup target confirmed
   long-term down.
6. ~~Work through the remaining 7 drift items~~ — done 2026-07-15/16: `authentik`, `gpu-operator`,
   `kube-prometheus-stack`, `rocketchat`, and `node-red` fixed (see "Resolved" above);
   `mariadb-operator` will be included in the ArgoCD list despite not being actively used yet;
   `open-webui` was already benign, no action needed.
7. ~~Resolve wes-chat's missing chart~~ — resolved 2026-07-16: it's a throwaway test app in its
   own repo, excluded from the migration entirely, not a real gap.
8. ~~Resolve immich-typesense-data~~ — done 2026-07-16, commented out, unused.
9. This checklist is now clean: 41 releases match live exactly, keycloak is deprecated,
   mariadb-operator is a known/accepted non-clean state, and wes-chat is intentionally excluded.
   Ready to start building the actual ArgoCD `Application`/`ApplicationSet` resources.
