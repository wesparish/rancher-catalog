# mariadb-operator-wes

Wrapper around the [MariaDB Operator](https://artifacthub.io/packages/helm/mariadb-operator/mariadb-operator) Helm chart (mmontes11/mariadb-operator).

## Install

1. **Install CRDs first (one-time):**
   ```bash
   helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator
   helm install mariadb-operator-crds mariadb-operator/mariadb-operator-crds -n <namespace>
   ```

2. **Install this chart:**
   ```bash
   helm dependency update
   helm -n <namespace> upgrade --install mariadb-operator-wes .
   ```

## Values

Values under `mariadb-operator:` are passed to the subchart. Metrics are enabled by default for Prometheus Operator (ServiceMonitor). See [subchart values](https://artifacthub.io/packages/helm/mariadb-operator/mariadb-operator?modal=values) for all options.
