#!/usr/bin/env bash
set -e

# download cert-manager and contour manifests
# remove x-kubernetes-preserve-unknown-fields field from cert-manager CRDs to make it compatible with Kubernets < 1.16

curl -sL https://github.com/jetstack/cert-manager/releases/download/v0.12.0/cert-manager.yaml > cert-manager-tmp.yaml
grep -v "x-kubernetes-preserve-unknown-fields" cert-manager-tmp.yaml > ./cert-manager/cert-manager.yaml
rm cert-manager-tmp.yaml

curl -sL https://projectcontour.io/quickstart/contour.yaml > ./contour/contour.yaml
