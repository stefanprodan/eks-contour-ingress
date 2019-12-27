# eks-envoy-ingress

This guide shows you how to set up a [GitOps](https://www.weave.works/blog/kubernetes-anti-patterns-let-s-do-gitops-not-ciops)
pipeline to securely expose Kubernetes services over HTTPS using:
* Amazon EKS and Route 53
* [cert-manager](https://cert-manager.io) to provision TLS certificates from [Let's Encrypt](https://letsencrypt.org)
* [Contour](https://projectcontour.io) as the [Envoy](https://www.envoyproxy.io/) based ingress controller
* [Flux](https://fluxcd.io) as the GitOps operator
* [podinfo](https://github.com/stefanprodan/podinfo) as the demo web application

![](docs/diagrams/eks-contour-cert-manager.png)

### Create an EKS cluster

You'll need an AWS account, a GitHub account, git and kubectl installed locally.

Install [eksctl](https://eksctl.io):

```sh
# macOS
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# windows
choco install eksctl
```

Create an EKS cluster with EC2 managed nodes:

```sh
cat << EOF | eksctl create cluster -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: my-cluster
  region: eu-west-1
managedNodeGroups:
  - name: controllers
    labels: { role: ingress }
    instanceType: m5.large
    desiredCapacity: 2
    volumeSize: 120
    iam:
      withAddonPolicies:
        certManager: true
        albIngress: true
  - name: workers
    labels: { role: apps }
    instanceType: m5.large
    desiredCapacity: 2
    volumeSize: 120
EOF
```

The above command creates an EKS cluster with two managed node groups:
* The controllers node group has the IAM roles needed by cert-manager to solve DNS01 ACME challenges and will be used to run 
the Envoy proxy DaemonSet along with Contour and cert-manager controller.
* The workers node group is for the apps that will be exposed outside the cluster by Envoy.

A Kustomize patch is used to pin the workloads on node groups, for example:

```
cat cert-manager/node-selector-patch.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  template:
    spec:
      nodeSelector:
        role: ingress
```

We use Kustomize patches so you don't have to modify the original manifests.

### Install Flux

[Flux](https://fluxcd.io) is a GitOps operator for Kubernetes that keeps your cluster state is sync with a Git repository.
Because Flux is pull based and also runs inside Kubernetes, you don't have to expose the cluster
credentials outside your production environment.

You can define the desired state of your cluster with Kubernetes YAML manifests and customise them with Kustomize.
Flux implements a control loop that continuously applies the desired state to your cluster,
offering protection against harmful actions like deployments deletion or policies altering.

![](docs/diagrams/flux-gitops-kustomize.png)

Install [fluxctl](https://github.com/fluxcd/flux/releases):

```sh
# macOS
brew install fluxctl

# Windows
choco install fluxctl

# Linux
curl -sL https://fluxcd.io/install | sh
```

On GitHub, fork this repository and clone it locally (replace `stefanprodan` with your GitHub username): 

```sh
git clone https://github.com/stefanprodan/eks-envoy-ingress
cd eks-envoy-ingress
```

Create the fluxcd namespace:

```sh
kubectl create ns fluxcd
```

Install Flux by specifying your fork URL (replace `stefanprodan` with your GitHub username): 

```bash
export GHUSER="stefanprodan" && \
fluxctl install \
--git-user=${GHUSER} \
--git-email=${GHUSER}@users.noreply.github.com \
--git-url=git@github.com:${GHUSER}/gitops-ingress \
--manifest-generation=true \
--namespace=fluxcd | kubectl apply -f -
```

### Setup Git sync

At startup, Flux generates a SSH key and logs the public key. Find the public key with:

```bash
fluxctl identity --k8s-fwd-ns fluxcd
```

In order to sync your cluster state with git you need to copy the public key and 
create a **deploy key** with **write access** on your GitHub repository.

Open GitHub, navigate to your repository, go to _Settings > Deploy keys_ click on _Add deploy key_, check 
_Allow write access_, paste the Flux public key and click _Add key_.

After a couple of seconds Flux will deploy Contour, cert-manager and podinfo in your cluster.

Check the sync status with:

```
watch kubectl get pods --all-namespaces
```

### Configure DNS

Retrieve the external address of Contour's Envoy load balancer:

```
kubectl get -n projectcontour service envoy -o wide

NAME    TYPE           CLUSTER-IP      EXTERNAL-IP
envoy   LoadBalancer   10.100.228.53   af4726981288e11eaade7062a36c250a-1448602599.eu-west-1.elb.amazonaws.com
```

Using the external address create a CNAME record in Route53 e.g. `*.example.com` that maps to the LB address.

Verify your DNS setup using the `host` command:

```
host podinfo.example.com

podinfo.example.com is an alias for af4726981288e11eaade7062a36c250a-1448602599.eu-west-1.elb.amazonaws.com.
```

### Configure Let's Encrypt wildcard certificate

Create a cluster issues using Let's Encrypt DNS01 solver (replace `stefanprodan` with your GitHub username):

```sh
export GHUSER="stefanprodan" && \
cat << EOF | tee ingress/issuer.yaml
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
  annotations:
    fluxcd.io/ignore: "false"
spec:
  acme:
    email: ${GHUSER}@users.noreply.github.com
    privateKeySecretRef:
      name: letsencrypt-prod
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - dns01:
        route53:
          region: eu-west-1
EOF
```

Create a certificate in the demo namespace (replace `example.com` with your domain):

```sh
export DOMAIN="example.com" && \
cat << EOF | tee ingress/cert.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: cert
  namespace: demo
  annotations:
    fluxcd.io/ignore: "false"
spec:
  secretName: cert
  commonName: "*.${DOMAIN}"
  dnsNames:
  - "*.${DOMAIN}"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
EOF
```

Apply changes via git:

```sh
git add -A && \
git commit -m "add wildcard cert" && \
git push origin master && \
fluxctl sync --k8s-fwd-ns fluxcd
```

Wait for the certificate to be issued:

```sh
watch kubectl -n demo describe certificate

Events:
  Type    Reason        Age    From          Message
  ----    ------        ----   ----          -------
  Normal  GeneratedKey  2m17s  cert-manager  Generated a new private key
  Normal  Requested     2m17s  cert-manager  Created new CertificateRequest resource "cert-1178588226"
  Normal  Issued        20s    cert-manager  Certificate issued successfully
```

When the certificate has been issued, cert-manager will create a secret with the TLS cert:

```sh
kubectl -n demo get secrets

NAME                  TYPE                                  DATA   AGE
cert                  kubernetes.io/tls                     3      5m40s
```

### Expose services over TLS

In order to expose the demo app podinfo outside the cluster you'll be using Contour's HTTPProxy custom resource definition. 

Create a HTTPProxy by referencing the TLS cert secret (replace `example.com` with your domain)::

```sh
export DOMAIN="example.com" && \
cat << EOF | tee ingress/proxy.yaml
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: podinfo
  namespace: demo
  annotations:
    fluxcd.io/ignore: "false"
spec:
  virtualhost:
    fqdn: podinfo.${DOMAIN}
    tls:
      secretName: cert
  routes:
  - services:
    - name: podinfo
      port: 9898
EOF
```

Apply changes via git:

```sh
git add -A && \
git commit -m "add podinfo ingress" && \
git push origin master && \
fluxctl sync --k8s-fwd-ns fluxcd
```

When TLS is enabled for a virtual host, Contour will redirect the traffic to the secure interface:

```sh
curl -vL podinfo.example.com

< HTTP/1.1 301 Moved Permanently
< location: https://podinfo.example.com/
```
