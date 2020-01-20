#!/usr/bin/env bash
set -e

if [[ ! -x "$(command -v eksctl)" ]]; then
    echo "eksctl not found"
    exit 1
fi

cat << EOF | eksctl create cluster -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: eu-west-1
nodeGroups:
  - name: controllers
    labels: { role: controllers }
    instanceType: m5.large
    desiredCapacity: 2
    iam:
      withAddonPolicies:
        certManager: true
        albIngress: true
    taints:
      controllers: "true:NoSchedule"
managedNodeGroups:
  - name: workers
    labels: { role: workers }
    instanceType: m5.large
    desiredCapacity: 2
    volumeSize: 120
EOF
