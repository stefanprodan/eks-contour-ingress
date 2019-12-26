# gitops-ingress

Securing Kubernetes ingress with Let's Encrypt the GitOps way

### Install Flux

You'll need a Kubernetes cluster v1.11 or newer with load balancer support, a GitHub account, git and kubectl installed locally.

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
git clone https://github.com/stefanprodan/gitops-ingress
cd gitops-ingress
```

Install Flux by specifying your fork URL (replace `stefanprodan` with your GitHub username): 

```bash
GHUSER="stefanprodan" \
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

After a couple of seconds Flux will deploy Contour and cert-manager in your cluster.

Check the sync status with:

```
watch kubectl get pods --all-namespaces
```
