## Introduction
This document describes how to run smoke tests against wallarm-ingress installation in local Kubernetes cluster.
Routines described in the document create local test environment and run smoke tests by performing the following actions:
* Build ingress controller image
* Create local Kubernetes cluster using kind
* Download helper images: ruby, python, collectd and wstore
* Download image with pytest and smoke tests
* Deploy Helm chart
* Deploy test workload with Httpbin
* Deploy pytest and run tests

## Prerequisites
### Software
The following software should be installed locally:
* [Docker](https://docs.docker.com/get-docker/)
* [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
* Golang `brew install go`
* helm `brew install helm`
* ggrep `brew install grep` (for Mac OS users)
### Access to container registry
Need to have an access (read-only is enough) to `dkr.wallarm.com/tests/smoke-tests` registry.
It is required to perform `docker login dkr.wallarm.com` using personal access token, before to run tests.
You should be able to make `docker pull dkr.wallarm.com/tests/smoke-tests`.
## Configuration
Create `.env` file in the root directory of the repository with the following content. All parameters which commented out are optional.
```
# Node base URL
# NODE_BASE_URL=http://wallarm-ingress-controller.default.svc

# Wallarm API settings. Used for Helm chart deployment and smoke tests
WALLARM_API_HOST=api.wallarm.com
WALLARM_API_TOKEN=...
WALLARM_API_CA_VERIFY=True

# Settings that related to smoke tests only
CLIENT_ID=...
USER_TOKEN=...


# Pytest arguments. Double quotes here must be used here
# PYTEST_ARGS="--allure-features=Node"

# Number of pytest workers. This variable is optional and set to 10 by default
# PYTEST_WORKERS=10

# Location of Pytest Docker image
# SMOKE_IMAGE_NAME=dkr.wallarm.com/tests/smoke-tests
# SMOKE_IMAGE_TAG=latest

# Just keep it here since it is used in main Makefile if we don't have GO installed locally
ARCH=amd64
```

In the project root there is an example `.env.example`, use `cp .env.example .env` to proceed.

## Running tests
* To create test environment and run tests for first time run `make kind-smoke-test`
* To run smoke tests against existing environment run `make smoke-test`
* To get access to local Kubernetes cluster set `export KUBECONFIG="$HOME/.kube/kind-config-ingress-smoke-test"`

If `SMOKE_IMAGE_*` or `WALALRM_API_*` variables were updated in `.env` file when environment was already exists,
run `make kind-smoke-test` to apply these changes.

## Cleanup
To delete test environment run:
```shell
kind delete cluster -n ingress-smoke-test
rm $HOME/.kube/kind-config-ingress-smoke-test
```
