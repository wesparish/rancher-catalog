#!/usr/bin/env bash
# Adopt existing cert-manager CRDs so Helm can manage them (required when CRDs
# were originally installed with kubectl apply instead of Helm).
# Run once before: helm -n cert-manager upgrade cert-manager . --reset-values
# CRD names from cert-manager v1.x
set -e
RELEASE_NAME="${1:-cert-manager}"
RELEASE_NAMESPACE="${2:-cert-manager}"

CRDS=(
  certificaterequests.cert-manager.io
  certificates.cert-manager.io
  challenges.acme.cert-manager.io
  clusterissuers.cert-manager.io
  issuers.cert-manager.io
  orders.acme.cert-manager.io
)

for crd in "${CRDS[@]}"; do
  if kubectl get crd "$crd" &>/dev/null; then
    echo "Adopting CRD: $crd"
    kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite
    kubectl annotate crd "$crd" \
      meta.helm.sh/release-name="$RELEASE_NAME" \
      meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" \
      --overwrite
  else
    echo "CRD not found (skipping): $crd"
  fi
done
echo "Done. If you are migrating from Bitnami, also delete Deployments with immutable selectors:"
echo "  kubectl -n $RELEASE_NAMESPACE delete deployment cert-manager-cainjector cert-manager-webhook"
echo "Then run: helm -n $RELEASE_NAMESPACE upgrade $RELEASE_NAME . --reset-values"
echo "If upgrade fails with webhook 'connection refused', wait for the webhook pod to be ready and run the upgrade again."
