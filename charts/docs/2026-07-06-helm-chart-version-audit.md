# Helm Chart Version Audit — 2026-07-06

## Summary

| # | Chart | Current | Latest | Gap | Complexity | New Features / Notes |
|---|-------|---------|--------|-----|------------|---------------------|
| 1 | **plex-wes (jellyfin)** | 10.11.6 | **10.11.11** | 5 patches | 🟢 Low | **7 security CVEs patched** (GHSA-j2hf, GHSA-8fw7, GHSA-v2jv, GHSA-jh22, GHSA-f47c, GHSA-jg92, GHSA-wwwm). Jellyfin team flagged pre-10.11.7 as "critically vulnerable." Drop-in tag bump. |
| 2 | **pihole** | 2024.07.0 | **2026.07.1** | ~2 years | 🔴 High | **Pi-hole v6 complete rewrite** — FTL now handles DNS+API+web server (replaces lighttpd+PHP). **6 dnsmasq CVEs patched** in 2026.05.0. All env vars changed to `FTLCONF_*` equivalents. Migration guide required. |
| 3 | **owncloud-wes** | 10.15.3 | **v10.16.3** | 1 minor | 🟡 Medium | **CVE-2026-40194** (phpseclib), user enumeration fix in password reset, storage error no longer leaks internal IPs. `db:convert-type` command removed; subadmin group-admin now off by default. |
| 4 | **nexus-wes** | 3.45.1 | **3.93.2** | 48 minors | 🔴 High | Go/Ansible/Alpine repo format support, PEP 658/691 for pip/Poetry/uv. **CRITICAL:** OrientDB removed in 3.71 — must upgrade to 3.70.5 first and migrate DB to H2 before continuing. Java 17+ required. |
| 5 | **frigate-wes** | 0.14.1-tensorrt | **0.17.2-tensorrt** | 3 minors | 🔴 High | Face recognition, LPR, CUDA Graphs for faster GPU inference, audio transcription, local model training. **CRITICAL:** `type: tensorrt` detector removed — must change to `type: onnx` and download new ONNX model. |
| 6 | **friendica-wes** | 2023.05-apache | **2026.05-apache** | 3 years | 🟡 Medium | BlueSky/ATproto integration, overhauled media embedding, channel performance improvements. PHP 8.1 minimum required (was 7.4). DB migration runs automatically on startup. |
| 7 | **zigbee2mqtt-wes** | 1.33.2 | **2.12.1** | Major bump | 🟡 Medium | Live external converter loading without restart, new OTA system with downgrade support, EmberZNet 9.1 support, hundreds of new devices. Config key renames — review changelog before upgrading. |
| 8 | **vllm** | v0.19.0 | **v0.24.0** | 5 minors | 🟢 Low | Model Runner V2 default (better throughput), FlashAttention 4 MLA prefill, Streaming Parser Engine for tool calls, chunked prefill, FP8 KV cache compression. Drop-in tag bump. |
| 9 | **plex-wes (ersatztv)** | v0.6.8 | **v26.5.1** | Calver switch | 🟡 Medium | Switched to calendar versioning. New Graphics Engine for channel overlays/watermarks, multi-server Jellyfin/Emby support. Config schema evolved significantly — review migration notes. |
| 10 | **open-webui-wes** | 12.10.0 (helm chart) | **15.2.0** | 3 major | 🟡 Medium | App 0.8.10 → 0.10.2: Terminal subchart, Kubernetes Secret refs for API keys/Redis, WebSocket improvements. Helm chart values structure changed across major versions — diff before upgrading. |
| 11 | **tandoor-wes** | 2.3.1 | **2.6.13** | 3 minors | 🟢 Low | Multiple shopping lists, iCal meal plan subscriptions, Cooklang importer, non-root container support. Standard Django migrations run on startup. |
| 12 | **tplink-omada-wes** | 6.2.0.17 | **6.2.10.17** | 10 patches | 🟢 Low | New `MONGOD_EXTRA_ARGS` and `JAVA_MAX_HEAP_SIZE`/`JAVA_MIN_HEAP_SIZE` env vars. Same major version, drop-in tag bump. |
| 13 | **freepbx-wes** | 15 | **15-5.1.1** | patch level | 🟢 Low | Asterisk 17.x support, Node 12 update, custom startup scripts via `/assets/custom-scripts/`. Pin to explicit tag instead of floating `15`. |
| 14 | **guacamole-wes** | 1.5.4 | **1.6.0** | 1 minor | 🟢 Low | Server-side protocol optimizer rewrite using worker threads (major bandwidth/rendering improvement), auto ARM support, env var auto-mapping. Drop-in upgrade. |
| 15 | **teamspeak3-wes** | 3.13 | **3.13.8** | patch level | 🟢 Low | Stability/security hardening; mainly value of pinning to `3.13.8` instead of floating `3.13` tag for reproducibility. |
| ✅ | rocketchat-wes | 8.6.0 | 8.6.0 | — | — | Up to date (upgraded 2026-07-04) |
| ✅ | tesla-wall-connector-exporter-wes | v0.5.2 | v0.5.2 | — | — | Up to date |
| ✅ | tasks-md-wes | 3.3.1-points | 3.3.1-points | — | — | Up to date |

## Suggested Upgrade Order

### Do first — security-driven, low effort (tag bump only)
- Jellyfin (plex-wes) → `10.11.11` — patches 7 CVEs
- vllm → `v0.24.0`
- tplink-omada-wes → `6.2.10.17`
- tandoor-wes → `2.6.13`
- guacamole-wes → `1.6.0`
- freepbx-wes → `15-5.1.1` (pin the tag)
- teamspeak3-wes → `3.13.8` (pin the tag)

### Plan time for — config migration needed
- owncloud-wes → `v10.16.3` (review subadmin default change)
- open-webui-wes → `15.2.0` (diff helm values across major versions)
- zigbee2mqtt-wes → `2.12.1` (review config key renames)
- friendica-wes → `2026.05-apache` (verify PHP 8.1 base image)
- plex-wes (ersatztv) → `v26.5.1` (review config schema changes)

### Schedule as projects — significant migration work
- **frigate-wes** — TensorRT → ONNX detector migration required before any version bump
- **pihole** — full Pi-hole v6 migration (env vars → `FTLCONF_*`, setupVars.conf → pihole.toml)
- **nexus-wes** — staged OrientDB → H2/PostgreSQL migration; must pass through 3.70.5 first

## Notes

- Audit performed by checking GitHub releases / Docker Hub tags for each chart's current image against upstream latest.
- Charts using `latest`, floating tags, or custom/mining images not actively tracked upstream were excluded from this audit.
- Re-run this audit periodically; upstream projects move fast (notably Pi-hole, Nexus, Frigate, zigbee2mqtt).
