# jitsi-wes

Wrapper around the [jitsi-meet](https://github.com/jitsi-contrib/jitsi-helm) chart (v1.5.1),
vendored under `charts/`.

## Local patch: stable XMPP secrets

`charts/jitsi-meet/templates/jicofo/xmpp-secret.yaml` and
`charts/jitsi-meet/templates/jvb/xmpp-secret.yaml` are patched from upstream. Upstream
regenerates `JICOFO_AUTH_PASSWORD`, `JICOFO_COMPONENT_SECRET`, and `JVB_AUTH_PASSWORD` with
`randAlphaNum` on every render with no way to preserve them short of pinning a plaintext value in
`values.yaml` — so every `helm upgrade` silently rotated these, breaking jicofo/jvb's XMPP auth
against prosody.

The patch adds a `lookup` against the existing Secret and reuses its value if present, only
generating fresh randomness on first install (same pattern used in `onlyoffice-wes`'s
`jwt-secret.yaml`).

**If `charts/jitsi-meet/` or `charts/jitsi-meet-1.5.1.tgz` is ever regenerated** (`helm dependency
update` / `helm dependency build`, or bumping the `jitsi-meet` version in `Chart.yaml`), this
patch will be silently overwritten. Re-apply it to both `xmpp-secret.yaml` files before deploying.

Note: `lookup` only resolves against a real cluster. Plain `helm template` (no cluster
connection) always renders the empty/random branch — use `helm template --dry-run=server`, or a
real `helm upgrade`/ArgoCD sync, to verify this class of fix.
