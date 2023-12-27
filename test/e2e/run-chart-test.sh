#!/bin/bash

# Copyright 2020 The Kubernetes Authors.
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

if [ -n "${DEBUG}" ]; then
  set -x
  KIND_LOG_LEVEL="6"
fi

set -o errexit
set -o nounset
set -o pipefail

cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name "${KIND_CLUSTER_NAME}" "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
  fi
}

trap cleanup EXIT ERR

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-nginx-dev}

if ! command -v kind --version &> /dev/null; then
  echo "kind is not installed. Use the package manager or visit the official site https://kind.sigs.k8s.io/"
  exit 1
fi

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=1.0.0-dev
export ARCH=${ARCH:-amd64}

# Uses a custom chart-testing image to avoid timeouts waiting for namespace deletion.
CT_IMAGE="quay.io/dmitriev/chart-testing:3.7.1"

HELM_EXTRA_ARGS="--timeout 180s"
HELM_EXTRA_SET_ARGS="\
 --set controller.wallarm.token=${WALLARM_API_TOKEN} \
 --set controller.wallarm.enabled=true \
 --set controller.image.repository=wallarm/ingress-controller \
 --set controller.image.tag=1.0.0-dev \
 --set controller.terminationGracePeriodSeconds=0 \
 --set controller.wallarm.tarantool.terminationGracePeriodSeconds=0 \
 --set fullnameOverride=wallarm-ingress"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  echo "[dev-env] creating Kubernetes cluster with kind"

  export K8S_VERSION=${K8S_VERSION:-v1.26.3@sha256:61b92f38dff6ccc29969e7aa154d34e38b89443af1a2c14e6cfbd2df6419c66f}

  # delete the cluster if it exists
  if kind get clusters | grep "${KIND_CLUSTER_NAME}"; then
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
  fi

  kind create cluster \
    --verbosity=${KIND_LOG_LEVEL} \
    --name "${KIND_CLUSTER_NAME}" \
    --config "${CURDIR}/test/e2e/kind.yaml" \
    --retain \
    --image "kindest/node:${K8S_VERSION}"

  echo "Kubernetes cluster:"
  kubectl get nodes -o wide

fi

if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  if ! command -v ginkgo &> /dev/null; then
    go install github.com/onsi/ginkgo/v2/ginkgo@v2.13.1
  fi
  echo "[dev-env] building image"
  make -C "${CURDIR}" clean-image build image
fi

KIND_WORKERS=$(kind get nodes --name="${KIND_CLUSTER_NAME}" | grep worker | awk '{printf (NR>1?",":"") $1}')
export KIND_WORKERS

echo "[dev-env] copying docker images to cluster..."
kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes="${KIND_WORKERS}" wallarm/ingress-controller:${TAG}

if [ "${SKIP_CERT_MANAGER_CREATION:-false}" = "false" ]; then
  curl -fsSL -o cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/download/v1.11.1/cmctl-linux-amd64.tar.gz
  tar xzf cmctl.tar.gz
  chmod +x cmctl
 ./cmctl help
  echo "[dev-env] apply cert-manager ..."
  kubectl apply --wait -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
  echo "[dev-env] waiting for cert-manager components available ..."
  kubectl wait --timeout=30s --for=condition=available deployment/cert-manager -n cert-manager
  echo "[dev-env] getting validation webhook config ..."
  kubectl get validatingwebhookconfigurations cert-manager-webhook -ojson | jq '.webhooks[].clientConfig'
  echo "[dev-env] getting cert-manager endpoints ..."
  kubectl get endpoints -n cert-manager cert-manager-webhook
  ./cmctl check api -n cert-manager --wait=2m
fi

echo "[dev-env] running helm chart e2e tests..."
docker run \
    --rm \
    --interactive \
    --network host \
    --name ct \
    --volume "${KUBECONFIG}":/root/.kube/config \
    --volume "${CURDIR}":/workdir \
    --workdir /workdir \
    ${CT_IMAGE} ct install \
        --charts charts/ingress-nginx \
        --helm-extra-set-args "${HELM_EXTRA_SET_ARGS}" \
        --helm-extra-args "${HELM_EXTRA_ARGS}"
