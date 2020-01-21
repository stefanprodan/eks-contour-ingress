# eks-contour-ingress

[![test](https://github.com/stefanprodan/eks-contour-ingress/workflows/test/badge.svg)](https://github.com/stefanprodan/eks-contour-ingress/actions)

This [guide](https://aws.amazon.com/blogs/containers/securing-eks-ingress-contour-lets-encrypt-gitops/)
shows you how to set up a [GitOps](https://www.weave.works/blog/kubernetes-anti-patterns-let-s-do-gitops-not-ciops)
pipeline to securely expose Kubernetes services over HTTPS using:
* Amazon EKS and Route 53
* [cert-manager](https://cert-manager.io) to provision TLS certificates from [Let's Encrypt](https://letsencrypt.org)
* [Contour](https://projectcontour.io) as the ingress controller
* [Flux](https://fluxcd.io) as the GitOps operator
* [podinfo](https://github.com/stefanprodan/podinfo) as the demo web application

![](docs/diagrams/eks-contour-cert-manager.png)

Read the guide on [AWS containers blog](https://aws.amazon.com/blogs/containers/securing-eks-ingress-contour-lets-encrypt-gitops/).
