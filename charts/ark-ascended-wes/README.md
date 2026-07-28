# ark-ascended-wes

ARK: Survival Ascended dedicated server (TheIsland_WP), the ASA successor to `charts/ark-wes`.

Standalone chart, deliberately not a Helm dependency on `jsknnr/ark-ascended-server` — see the
comment at the top of `Chart.yaml` for why. It borrows that image and its env-var contract
(`SESSION_NAME`, `SERVER_MAP`, `MODS`, `EXTRA_SETTINGS`, …) and ships its own Deployment, Service
and ConfigMap.

## Deploying

ArgoCD is not live yet, so this deploys with plain Helm. The entry in
`charts/argocd/applicationset.yaml` is bookkeeping for when ArgoCD does get bootstrapped.

```bash
kubectl create namespace ark-ascended

# Passwords never live in git. server-password empty = public server (no join password).
kubectl create secret generic ark-ascended-server -n ark-ascended \
  --from-literal=server-admin-password='<real password>' \
  --from-literal=server-password=''

# PV/PVC first -- the PVC is namespaced, so the namespace must already exist.
kubectl apply -f ../storage/ark-ascended.yaml

helm upgrade --install ark-ascended . -n ark-ascended
```

The chart hard-fails to render without `existingSecret`, so there is no path where it quietly
deploys a server with no admin password.

### Storage prerequisite

`charts/storage/ark-ascended.yaml` is a **static** cephfs CSI volume (`staticVolume: "true"`),
which means `rootPath` must already exist on cephfs — the mount will not create it. Before first
apply:

```
/k8s-volumes/ark-ascended/data/    owned 10000:10000, mode 0777
```

The container runs as uid/gid `10000` (`steam`), and the `game-ini` initContainer writes into the
volume at every pod start, so it must be writable. cephfs CSI does not reliably apply the pod's
`fsGroup` to static volumes, hence setting it on disk. Create it either from `w-dock5.weshouse`
(cephfs is mounted at `/mnt/ceph-fs/k8s-volumes/`) or from a throwaway pod in namespace `borg`
mounting the `borg-backup-cephfs` PVC, which maps cephfs root.

Do **not** use the in-tree `cephfs:` volume plugin here — Kubernetes removed it in 1.31 and this
cluster is 1.31.4.

The volume covers the whole ARK install directory (`/home/steam/ark`), not just
`ShooterGame/Saved`. That is deliberate: mounting only `Saved` means every pod restart or
reschedule re-downloads the entire game through steamcmd.

## Mods

The vanilla server was brought up first so that the steamcmd install, the cephfs volume and the
LoadBalancer could be verified in isolation — bad CurseForge IDs fail at startup in ways that are
hard to tell apart from storage or network problems. All five below are now enabled and verified
loading in-game.

ASA uses CurseForge project IDs, not Steam Workshop IDs, so the ASE list in
`charts/ark-wes/values.yaml` does not carry over directly. Verified mapping:

| ASE mod (Steam Workshop ID) | ASA equivalent | CurseForge project ID |
|---|---|---|
| Awesome SpyGlass! (1404697612) | Awesome Spyglass! | `947033` |
| Awesome Teleporters! (889745138) | Awesome Teleporters! | `950914` |
| Automatic Death Recovery (1315534671) | AP: Death Recovery [Cross-platform] (same author, elkay) | `929578` |
| Dino Storage v2 (1609138312) | Dino Depot (DelilahEve) — different mod, same role | `942024` |
| Revive my dino (1957185915) | AP+ Revive My Dino - Dino Resurrection | `1086659` |
| Dino Tracker (924933745) | **no direct ASA port** | — |

Notes:

- **Dino Storage v2 has no ASA port.** `Dino Depot` is a substitute cryopod-replacement, not the
  same mod — saved dinos do not transfer, and its ~200 config options were not tuned.
- **Dino Tracker has no ASA port either.** Nothing on CurseForge is a port of 924933745. Closest
  functional equivalents if it's wanted: Dino Radar, Dino Scanner, Ascended Dino Scanner, Der Dino
  Finder, Simple Creature Finder. Note that Awesome Spyglass already covers part of what Dino
  Tracker was used for.

Set `env.mods` to a comma-separated list of project IDs. Mods download on the first pod start
after the list changes, so expect a slow boot then.

## Settings

Both config files are managed declaratively. `gameIni` and `gameUserSettingsIni` are rendered into
a ConfigMap and copied over `ShooterGame/Saved/Config/WindowsServer/{Game,GameUserSettings}.ini` by
the `game-ini` initContainer on **every** pod start.

- **`gameUserSettingsIni`** → `GameUserSettings.ini` `[ServerSettings]` — server rates, PVE/PVP,
  RCON. The image's entrypoint only creates this file when it is absent, and otherwise only
  rewrites the RCON lines, so a file written here survives. Keep `RCONEnabled`/`RCONPort` in it to
  match what the entrypoint expects to find.
- **`gameIni`** → `Game.ini` `[/script/shootergame.shootergamemode]` — settings with no
  `GameUserSettings.ini` equivalent.

Because both are rewritten each start, settings changed in-game or by an admin revert on the next
restart. Change `values.yaml` instead.

### Do not use `env.extraSettings` — the image mangles launch args

`env.extraSettings` is deliberately empty, and `env.sessionName` must not contain spaces. The
entrypoint builds one `?`-delimited launch string and then expands it **unquoted**:

```bash
LAUNCH_COMMAND="${SERVER_MAP}?SessionName=${SESSION_NAME}?RCONEnabled=True?RCONPort=${RCON_PORT}"
# ... EXTRA_SETTINGS appended ...
proton run .../ArkAscendedServer.exe ${LAUNCH_COMMAND} &     # <-- unquoted
```

Any space in `SESSION_NAME` word-splits that into separate argv elements, and ARK parses `?`
options from the first element only — silently discarding everything after the space. This was hit
in practice: `SESSION_NAME="WTopAce Ascended Island"` with
`extraSettings="?TamingSpeedMultiplier=40.0?XPMultiplier=4.0?ServerPVE=True"` produced a server
advertised as `WTopAce` running **vanilla rates**, with no error anywhere in the logs. RCON still
worked, which is misleading — the entrypoint writes those two keys to `GameUserSettings.ini`
directly rather than relying on the launch args.

Hence the underscores in `WTopAce_Ascended_Island`, and hence settings living in
`gameUserSettingsIni` rather than in launch args. ARK also does not persist launch-arg overrides to
disk, so the file-based approach is verifiable: `grep` the ini in the running pod and the settings
are either there or they are not.

### Not yet audited

Only the headline settings were carried over from ASE: taming 40x, XP 4x, PVE, plus the `Game.ini`
block in `values.yaml`. The rest of the old `GameUserSettingsIni` block in
`charts/ark-wes/values.yaml` has **not** been compared line-by-line against ASA defaults. Per-level
stat multiplier arrays were deliberately left at ASA defaults — revisit if taming/breeding turns
out too easy.

## Networking

| | |
|---|---|
| LoadBalancer IP | `172.16.1.238` (metallb pool `172.16.1.220-240`) |
| Game port | `7778/UDP` — not the ASA default 7777, which satisfactory already uses |
| RCON port | `27020/TCP` (uses the admin password from the Secret) |

ASA needs no Steam query port — unlike ASE it uses the Epic-backed server list, discovered over
outbound connections. The RCON port should not be reachable from outside the LAN.

The `metallb.universe.tf/allow-shared-ip` key is `ark-ascended`, deliberately different from the
literal `sharing-key` that `charts/ark-wes` uses at `.233`, so the two ARK servers can never be
co-assigned onto one address.

