#!/bin/bash

cat > helm-output.yaml
kubectl kustomize
rm helm-output.yaml