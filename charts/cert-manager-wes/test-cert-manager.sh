#!/usr/bin/env bash
# Quick test that cert-manager is working.
#   test       - self-signed cert (no DNS/HTTP)
#   test-real  - real TLS cert for cert-manager-test.elastiscale.net via Let's Encrypt (DNS must point to your ingress)
# Usage: ./test-cert-manager.sh [test|test-real|cleanup|status]
set -e
NAMESPACE="${TEST_NAMESPACE:-cert-manager-test}"
REAL_DOMAIN="${REAL_DOMAIN:-cert-manager-test.elastiscale.net}"
CLUSTER_ISSUER="${CLUSTER_ISSUER:-letsencrypt-production}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"

status() {
  echo "=== cert-manager pods ==="
  kubectl -n cert-manager get pods -l app.kubernetes.io/instance=cert-manager
  echo ""
  echo "=== ClusterIssuers ==="
  kubectl get clusterissuers
  echo ""
  echo "=== Certificates in $NAMESPACE (if namespace exists) ==="
  kubectl get certificates -n "$NAMESPACE" 2>/dev/null || true
}

test_cm() {
  echo "Creating test namespace: $NAMESPACE"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo "Creating self-signed Issuer and Certificate..."
  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: $NAMESPACE
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: $NAMESPACE
spec:
  secretName: test-cert-tls
  duration: 24h
  renewBefore: 12h
  subject:
    organizations:
      - cert-manager-test
  commonName: test.example.com
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
EOF

  echo "Waiting for Certificate to be Ready (up to 60s)..."
  if kubectl wait --for=condition=Ready certificate/test-cert -n "$NAMESPACE" --timeout=60s 2>/dev/null; then
    echo "SUCCESS: Certificate is Ready."
    kubectl get certificate test-cert -n "$NAMESPACE"
    echo ""
    echo "TLS secret created:"
    kubectl get secret test-cert-tls -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates 2>/dev/null || true
  else
    echo "Certificate not ready. Check: kubectl describe certificate test-cert -n $NAMESPACE"
    exit 1
  fi
}

test_real() {
  echo "Creating test namespace: $NAMESPACE"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  echo "Creating backend Deployment and Service..."
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: real-domain-backend
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: real-domain-backend
  template:
    metadata:
      labels:
        app: real-domain-backend
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: real-domain-backend
  namespace: $NAMESPACE
spec:
  selector:
    app: real-domain-backend
  ports:
    - port: 80
      targetPort: 80
EOF

  echo "Creating Certificate and Ingress with TLS for $REAL_DOMAIN (ClusterIssuer: $CLUSTER_ISSUER)..."
  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: real-domain-tls
  namespace: $NAMESPACE
spec:
  secretName: real-domain-tls
  issuerRef:
    name: $CLUSTER_ISSUER
    kind: ClusterIssuer
  dnsNames:
    - $REAL_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: real-domain-ingress
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: $CLUSTER_ISSUER
spec:
  ingressClassName: $INGRESS_CLASS
  tls:
    - hosts:
        - $REAL_DOMAIN
      secretName: real-domain-tls
  rules:
    - host: $REAL_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: real-domain-backend
                port:
                  number: 80
EOF

  echo "Waiting for backend pod..."
  kubectl wait --for=condition=Available deployment/real-domain-backend -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  echo "Waiting for Certificate to be Ready (HTTP-01 can take 1–3 min)..."
  if kubectl wait --for=condition=Ready certificate/real-domain-tls -n "$NAMESPACE" --timeout=300s 2>/dev/null; then
    echo "SUCCESS: Certificate is Ready for $REAL_DOMAIN"
    kubectl get certificate real-domain-tls -n "$NAMESPACE"
    kubectl get ingress real-domain-ingress -n "$NAMESPACE"
    echo ""
    echo "TLS secret:"
    kubectl get secret real-domain-tls -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true
  else
    echo "Certificate not ready. Check: kubectl describe certificate real-domain-tls -n $NAMESPACE"
    echo "Ensure $REAL_DOMAIN resolves to your ingress and HTTP-01 is reachable."
    exit 1
  fi
}

cleanup() {
  echo "Deleting test namespace: $NAMESPACE"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --timeout=60s
  echo "Cleanup done."
}

case "${1:-test}" in
  test)      test_cm ;;
  test-real) test_real ;;
  cleanup)   cleanup ;;
  status)    status ;;
  *)         echo "Usage: $0 [test|test-real|cleanup|status]"; exit 1 ;;
esac
