# Refund Hunter DevOps Tools

This repo contains the scripts and instructions necessary to create the Refund Hunter runtime
environment from scratch, and various tools to manage the infrastructure once its up and
running. The infrastructure consists of four *public-cloud* hosted Kubernetes clusters called
*environments*:

1. `ops` - This is a high availability Kubernetes cluster used to host critical services. The list
   of critical services include:
   * GitLab - Git repository server hosted at `git.<DOMAIN_NAME>`, used to store all source code
     and configuration data, as well as running CI/CD pipelines.
   * `dev` control plane - development environment Kubernetes control plane for self managed nodes
     hosted at `dev.<DOMAIN_NAME>`
   * `pre` control plane - QA environment Kubernetes control plane for self-managed nodes hosted at
     `pre.<DOMAIN_NAME>`
   * `prd` control plane - production environment Kubernetes control plane for self managed nodes
     hosted at `prd.<DOMAIN_NAME>`
2. `dev` - Kubernetes cluster for developers to test code under development.
3. `pre` - Kubernetes cluster for integration testing of pre-production code.
4. `prd` - Kubernetes cluster hosting production code.

In addition to the four *public-cloud* hosted Kubernetes clusters, there are three self-managed
Kubernetes clusters, one each for `dev`, `pre`, and `prd` environments. For these self-managed
clusters, the control plane runs as pods in the `ops` cluster, while worker nodes are either
cloud-hosted VMs or physical machines added into the cluster via publicly accessible IP addresses.

The name of each cluster follow the general schema `<DOMAIN_PREFIX><ENVIRONMENT><TYPE_SUFFIX>`.
`<DOMAIN_PREFIX>` is shorthand for the domain, in the case of Refund Hunter it is `rh-`.
`<ENVIRONMENT>` is one of `ops`, `dev`, `pre`, or `prd`. `<TYPE_SUFFIX>` is either `-sm` for
self-managed cluster or `-ch` for cloud-hosted cluster.

### Configuration Data and Secrets

The `<ENVIRONMENT>` name maps directly to a Git branch so that configuration data can be stored
directly in Git repo. The configuration for each environment is stored in its own encrypted Git
submodule, with unique decryption key for each environment. By convention, configuration submodules
are not shared between source code repos. This creates an additional layer of isolation to guard
against code leaks.

Using this `devops` repo as an example, it has configuration for all four environments, which are
stored as Git submodules under the `.modules` folder. To create a configuration submodule, first
create an empty Git repo, then add it as a submodule under the `.modules` folder:

```
git submodule add ${CONFIG_REPO} ${ENVIRONMENT}
```

