# Helm Chart Version Audit — 2026-07-06

## Summary

| # | Chart | Current | Latest | Gap | Complexity | New Features / Notes |
|---|-------|---------|--------|-----|------------|---------------------|
| 1 | **pihole** | 2024.07.0 | **2026.07.1** | ~2 years | 🔴 High | **Pi-hole v6 complete rewrite** — FTL now handles DNS+API+web server (replaces lighttpd+PHP). **6 dnsmasq CVEs patched** in 2026.05.0. All env vars changed to `FTLCONF_*` equivalents. Migration guide required. |
| 2 | **frigate-wes** | 0.14.1-tensorrt | **0.17.2-tensorrt** | 3 minors | 🔴 High | Face recognition, LPR, CUDA Graphs for faster GPU inference, audio transcription, local model training. **CRITICAL:** `type: tensorrt` detector removed — must change to `type: onnx` and download new ONNX model. |
| 3 | **vllm** | v0.19.0 | **v0.24.0** | 5 minors | 🟢 Low | Model Runner V2 default (better throughput), FlashAttention 4 MLA prefill, Streaming Parser Engine for tool calls, chunked prefill, FP8 KV cache compression. Drop-in tag bump. Note: chart's model config/VRAM settings were retuned 2026-07-07, but the base `vllm/vllm-openai` image itself is still v0.19.0. |
| 4 | **tandoor-wes** | 2.3.1 | **2.6.13** | 3 minors | 🟢 Low | Multiple shopping lists, iCal meal plan subscriptions, Cooklang importer, non-root container support. Standard Django migrations run on startup. |
| 5 | **tplink-omada-wes** | 6.2.0.17 | **6.2.10.17** | 10 patches | 🟢 Low | New `MONGOD_EXTRA_ARGS` and `JAVA_MAX_HEAP_SIZE`/`JAVA_MIN_HEAP_SIZE` env vars. Same major version, drop-in tag bump. |
| ✅ | **owncloud-wes** | 10.16.3 | 10.16.3 | — | — | Upgraded 2026-07-07 (was 10.15.3). Patches CVE-2026-40194, user enumeration, storage info leak; subadmin group-admin now restricted. DB backed up before upgrade (238MB dump); `occ upgrade` ran automatically on container start with no errors. Verified via `/status.php`. |
| 🚫 | **guacamole-wes** | 1.5.4 | 1.6.0 — **won't upgrade** | — | — | **Attempted and rolled back 2026-07-08.** Guacamole 1.6.0's Docker entrypoint switched to runtime env-var config (`enable-environment-properties: true`) instead of baking values into `guacamole.properties`. Kubernetes auto-injects a legacy `GUACAMOLE_POSTGRESQL_PORT=tcp://<ip>:<port>` var (from the `guacamole-postgresql` Service in-namespace) that collides with Guacamole's own property-name lookup, which expects a plain integer — the JDBC Postgres auth extension fails to load silently, causing **all** logins to fail with a generic invalid-credentials error. Root cause confirmed via container env/log inspection; DB data was verified untouched (not the cause). Requires `enableServiceLinks: false` on the pod spec to fix, which the upstream `guacamole` subchart (beryju.org, 1.4.1) doesn't expose — would need vendoring/patching the subchart. Rolled back cleanly to 1.5.4; the one applied DB migration (`ALTER TYPE ... ADD VALUE 'AUDIT'`) is additive and harmless on 1.5.4, left in place. |
| ✅ | **open-webui-wes** | 15.2.0 | 15.2.0 | — | — | Upgraded 2026-07-07 (was 12.10.0, app 0.8.10→0.10.2). No values.yaml breaking changes. DB backed up before migration (irreversible per upstream); Alembic migration ran clean. Post-upgrade required a Redis + pod restart to clear stale pre-upgrade session/lock state that was causing hung replies. |
| ✅ | **plex-wes (jellyfin)** | 10.11.11 | 10.11.11 | — | — | Upgraded 2026-07-06 (was 10.11.6). Patches 7 security CVEs. Verified clean startup, DB migration applied, hardware transcoding intact. |
| ✅ | **zigbee2mqtt-wes** | 2.12.1 | 2.12.1 | — | — | Upgraded 2026-07-06 (was 1.33.2). Config auto-migrated on startup; verified clean coordinator reconnect and HA discovery republish. |
| ✅ | rocketchat-wes | 8.6.0 | 8.6.0 | — | — | Up to date (upgraded 2026-07-04) |
| ✅ | tesla-wall-connector-exporter-wes | v0.5.2 | v0.5.2 | — | — | Up to date |
| ✅ | tasks-md-wes | 3.3.1-points | 3.3.1-points | — | — | Up to date |
| ➖ | ~~plex-wes (ersatztv)~~ | v0.6.8 | v26.5.1 (final release) | — | — | **Removed 2026-07-06.** Found never actually deployed — orphaned `values.yaml` config with no template. Project archived April 2026 (discontinued for ground-up rewrite); later releases moved to `ghcr.io/ersatztv/legacy`. Config removed rather than deployed fresh. |
| ➖ | ~~plex-wes (readarr)~~ | latest | — | — | — | **Removed 2026-07-06.** Deployment was broken (0/1, crash state) and unused. Deleted deployment/service/ingress templates and values.yaml config. |
| ➖ | ~~nexus-wes~~ | 3.45.1 | 3.93.2 | — | — | **Removed from tracking 2026-07-07.** Namespace `nexus` exists but has zero pods and no helm release — not actually deployed. |
| ➖ | ~~freepbx-wes~~ | 15 | 15-5.1.1 | — | — | **Removed from tracking 2026-07-07.** Namespaces `freepbx-wes`/`freepbx-wes-pkqqr` exist but have zero pods and no helm release — not actually deployed. |
| ➖ | ~~teamspeak3-wes~~ | 3.13 | 3.13.8 | — | — | **Removed from tracking 2026-07-07.** Namespace `teamspeak3` exists but has zero pods and no helm release — not actually deployed. |
| ➖ | ~~friendica-wes~~ | 2023.05-apache | 2026.05-apache | — | — | **Removed from tracking 2026-07-07.** Namespace `friendica` exists but has zero pods and no helm release — not actually deployed. |

## Suggested Upgrade Order

### Do first — security-driven, low effort (tag bump only)
- vllm → `v0.24.0`
- tplink-omada-wes → `6.2.10.17`
- tandoor-wes → `2.6.13`

### Schedule as projects — significant migration work
- **frigate-wes** — TensorRT → ONNX detector migration required before any version bump
- **pihole** — full Pi-hole v6 migration (env vars → `FTLCONF_*`, setupVars.conf → pihole.toml)
- **guacamole-wes** — vendor/patch the `guacamole` subchart to set `enableServiceLinks: false` before retrying 1.6.0

## Notes

- Audit performed by checking GitHub releases / Docker Hub tags for each chart's current image against upstream latest.
- Charts using `latest`, floating tags, or custom/mining images not actively tracked upstream were excluded from this audit.
- Re-run this audit periodically; upstream projects move fast (notably Pi-hole, Nexus, Frigate, zigbee2mqtt).
