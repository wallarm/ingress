#!/bin/bash

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

KIND_LOG_LEVEL="1"

if ! [ -z $DEBUG ]; then
  set -x
  KIND_LOG_LEVEL="6"
fi

set -o errexit
set -o nounset
set -o pipefail

cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME}
  fi
}

trap cleanup EXIT

[[ "${CI:-}" == "true" ]] && unset KUBERNETES_SERVICE_HOST

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-nginx-dev}

if ! command -v kind --version &> /dev/null; then
  echo "kind is not installed. Use the package manager or visit the official site https://kind.sigs.k8s.io/"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=1.0.0-dev
export ARCH=${ARCH:-amd64}
export REGISTRY=wallarm

NGINX_BASE_IMAGE=$(cat $DIR/../../NGINX_BASE)

echo "Running e2e with nginx base image ${NGINX_BASE_IMAGE}"

export NGINX_BASE_IMAGE=$NGINX_BASE_IMAGE

export DOCKER_CLI_EXPERIMENTAL=enabled

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

export WALLARM_ENABLED="${WALLARM_ENABLED:-false}"

export WALLARM_API_TOKEN="${WALLARM_API_TOKEN:-}"

export IS_CHROOT="${IS_CHROOT:-false}"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  echo "[dev-env] creating Kubernetes cluster with kind"

  export K8S_VERSION=${K8S_VERSION:-v1.25.2@sha256:9be91e9e9cdf116809841fc77ebdb8845443c4c72fe5218f3ae9eb57fdb4bace}

  kind create cluster \
    --verbosity=${KIND_LOG_LEVEL} \
    --name ${KIND_CLUSTER_NAME} \
    --config ${DIR}/kind.yaml \
    --retain \
    --image "kindest/node:${K8S_VERSION}"

  echo "Kubernetes cluster:"
  kubectl get nodes -o wide
fi

if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  if ! command -v ginkgo &> /dev/null; then
    go get github.com/onsi/ginkgo/v2/ginkgo@v2.1.4
  fi

  echo "[dev-env] building image"
  make -C ${DIR}/../../ clean-image build image image-chroot
  echo "[dev-env] .. done building controller images"
  echo "[dev-env] now building e2e-image.."
  make -C ${DIR}/../e2e-image image
  echo "[dev-env] ..done building e2e-image"
fi

# Preload images used in e2e tests
export KIND_WORKERS=$(kind get nodes --name="${KIND_CLUSTER_NAME}" | grep worker | awk '{printf (NR>1?",":"") $1}')

echo "[dev-env] copying docker images to cluster..."

kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes=${KIND_WORKERS} nginx-ingress-controller:e2e

if [ "${IS_CHROOT}" == "true" ]; then
  echo "Using chroot image ..."
  set -x
  docker tag ${REGISTRY}/ingress-controller-chroot:${TAG} ${REGISTRY}/ingress-controller:${TAG}
  set +x
  docker images
fi

kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes=${KIND_WORKERS} ${REGISTRY}/ingress-controller:${TAG}

if [ "${WALLARM_ENABLED}" == "true" ]; then
  if [ -z "${WALLARM_API_TOKEN}" ]; then
    echo "WALLARM_API_TOKEN must be set! Exiting ..."
    exit 1
  fi

  echo "[dev-env] copying helper images to cluster..."
  ${DIR}/../../build/load-images.sh
fi

echo "[dev-env] running e2e tests..."
make -C ${DIR}/../../ e2e-test
