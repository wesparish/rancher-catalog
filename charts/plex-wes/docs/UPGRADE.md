# plex-wes Upgrade Plan

_Last updated: 2026-03-24_

## Image Inventory

| Service | Image | Current Tag | Current Version | Latest Version | Status |
|---------|-------|-------------|-----------------|----------------|--------|
| plex | `plexinc/pms-docker` | `plexpass` | 1.43.0.10492 | 1.43.0.10492 | Rolling tag — OK |
| deluge | `wesparish/deluge` | `latest` | Unknown | Unknown | Personal image — no update needed |
| tautulli | `tautulli/tautulli` | `latest` | v2.16.1 | v2.16.1 | Rolling tag — OK |
| radarr | `ghcr.io/hotio/radarr` | `release` | 6.0.4.10291 | 6.0.4.10291 | Rolling tag — OK |
| sonarr | `ghcr.io/hotio/sonarr` | `release` | 4.0.17.2952 | 4.0.17.2952 | Rolling tag — OK |
| readarr | `ghcr.io/hotio/readarr` | `latest` | 0.4.18.2805 | 0.4.18.2805 | Upstream archived June 2025 |
| prowlarr | `ghcr.io/hotio/prowlarr` | `testing` | 2.3.4.5307 | 2.3.4.5307 | Rolling tag — OK |
| lidarr | `ghcr.io/hotio/lidarr` | `release` | 3.1.0.4875 | 3.1.0.4875 | Rolling tag — OK |
| overseerr | `ghcr.io/hotio/overseerr` | `latest` | v1.34.0 | v1.34.0 | Migrate to `hotio/seerr` for v3 |
| qbittorrent | `ghcr.io/hotio/qbittorrent` | `release` | 5.1.4 | 5.1.4 | Rolling tag — OK |
| jellyfin | `ghcr.io/jellyfin/jellyfin` | **`10.10.5`** | 10.10.5 | 10.11.6 | **Pinned — needs update** |
| watchstate | `ghcr.io/arabcoders/watchstate` | `latest` | v1.0.8 | v1.0.8 | Rolling tag — OK |
| maintainerr | `ghcr.io/jorenn92/maintainerr` | `latest` | v3.1.0 | v3.1.0 | Rolling tag — OK |
| qbittorrent-exporter | `caseyscarborough/qbittorrent-exporter` | `latest` | v1.3.5 | v1.3.5 | Rolling tag — OK |

---

## Action Items

### 1. Jellyfin: 10.10.5 → 10.11.6

**Priority: High**

10.11.x is a major release that migrated from XML-based databases to EF Core (SQLite). Key improvements:
- Significant performance improvements on large libraries
- Database consolidation (multiple XML files → single SQLite DB)
- This migration is **one-way** — back up config before upgrading

**Steps:**
1. Back up the `jellyfin-config` PVC (or snapshot the PV)
2. Update `values.yaml`: `tag: 10.11.6`
3. Deploy and verify the DB migration completes successfully
4. Check the Jellyfin logs for migration errors before declaring success

---

### 2. Overseerr → Seerr v3 Migration

**Priority: Low**

hotio.dev now recommends migrating from `hotio/overseerr` to `ghcr.io/hotio/seerr` (Seerr v3). The `overseerr` image still works but Seerr v3 is the actively maintained fork.

**Steps:**
1. Review https://hotio.dev/containers/seerr/ for migration notes
2. Update `values.yaml` image to `ghcr.io/hotio/seerr:release`
3. Verify data migration from existing overseerr PVC

---

### 3. Readarr: Upstream archived (June 2025)

**Priority: Informational**

The Readarr project was archived upstream in June 2025. `ghcr.io/hotio/readarr` still publishes builds but upstream development has ceased. No action required now, but plan for a replacement if Readarr starts breaking.

---

## Upgrade Order

For the immediate release, prioritize by risk and impact:

1. **Jellyfin 10.11.6** — active users, meaningful improvements, one-way DB migration (plan a maintenance window)
2. **Overseerr → Seerr** — evaluate during a low-activity window
3. **Readarr** — monitor for breakage, plan replacement if upstream death causes issues
