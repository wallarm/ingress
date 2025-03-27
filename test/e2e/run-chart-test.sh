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

# generate unique group name
export NODE_GROUP_NAME="gitlab-ingress-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12; echo)"

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
export TAG=${TAG:-1.0.0-dev}
export ARCH=${ARCH:-amd64}
export REGISTRY=${REGISTRY:=wallarm}

# Uses a custom chart-testing image to avoid timeouts waiting for namespace deletion.
CT_IMAGE="quay.io/dmitriev/chart-testing:3.7.1"

# This will prevent the secret for index.docker.io from being used if the DOCKERHUB_USER is not set.
DOCKERHUB_REGISTRY_SERVER="https://index.docker.io/v1/"

if [ "${DOCKERHUB_USER:-false}" = "false" ]; then
  DOCKERHUB_REGISTRY_SERVER="fake_docker_registry_server"
fi

DOCKERHUB_SECRET_NAME="dockerhub-secret"
DOCKERHUB_USER="${DOCKERHUB_USER:-fake_user}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-fake_password}"

CT_CONFIG="${CT_CONFIG:-$HOME/.kube/kind-config-ct-$KIND_CLUSTER_NAME}"

HELM_EXTRA_ARGS="${HELM_EXTRA_ARGS:---timeout 240s}"
HELM_EXTRA_SET_ARGS="\
 --set controller.wallarm.enabled=true \
 --set controller.wallarm.apiHost=${WALLARM_API_HOST} \
 --set controller.wallarm.token=${WALLARM_API_TOKEN} \
 --set controller.wallarm.nodeGroup=${NODE_GROUP_NAME} \
 --set controller.image.repository=${REGISTRY}/ingress-controller \
 --set controller.image.tag=${TAG} \
 --set controller.terminationGracePeriodSeconds=0 \
 --set controller.wallarm.postanalytics.terminationGracePeriodSeconds=0 \
 --set fullnameOverride=wallarm-ingress"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  echo "[dev-env] creating Kubernetes cluster with kind"

  export K8S_VERSION=${K8S_VERSION:-v1.32.3@sha256:b36e76b4ad37b88539ce5e07425f77b29f73a8eaaebf3f1a8bc9c764401d118c}

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
    go install github.com/onsi/ginkgo/v2/ginkgo@v2.23.3
  fi
  echo "[dev-env] building image"
  make -C "${CURDIR}" clean-image build image
fi

if [[ "${CI:-}" == "true" ]]; then
  KIND_WORKERS=$(kind get nodes --name="${KIND_CLUSTER_NAME}" | grep worker | awk '{print $1}')
  for NODE in $KIND_WORKERS; do
      docker exec "${NODE}" bash -c "cat >> /etc/containerd/config.toml <<EOF
[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"registry-1.docker.io\".auth]
  username = \"$DOCKERHUB_USER\"
  password = \"$DOCKERHUB_PASSWORD\"
[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"$CI_REGISTRY\".auth]
  username = \"$CI_REGISTRY_USER\"
  password = \"$CI_REGISTRY_PASSWORD\"
EOF
systemctl restart containerd"
  done
fi

KIND_WORKERS=$(kind get nodes --name="${KIND_CLUSTER_NAME}" | grep worker | awk '{printf (NR>1?",":"") $1}')
export KIND_WORKERS

echo "[dev-env] copying docker images to cluster..."
kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes="${KIND_WORKERS}" ${REGISTRY}/ingress-controller:${TAG}

if [ "${SKIP_CERT_MANAGER_CREATION:-false}" = "false" ]; then
  echo "[dev-env] deploying cert-manager..."
  # Download cmctl. Cannot validate checksum as OS & platform may vary.
  curl --fail --location "https://github.com/cert-manager/cmctl/releases/download/v2.1.1/cmctl_$(uname -s)_$([ $(uname -m) = "x86_64" ] && echo amd64 || echo arm64).tar.gz" | tar --extract --gzip cmctl

  kubectl create namespace cert-manager
  kubectl -n cert-manager create secret docker-registry ${DOCKERHUB_SECRET_NAME} \
    --docker-server=${DOCKERHUB_REGISTRY_SERVER} \
    --docker-username="${DOCKERHUB_USER}" \
    --docker-password="${DOCKERHUB_PASSWORD}" \
    --docker-email=docker-pull@unexists.unexists || true
  echo "[dev-env] apply cert-manager ..."
  ./cmctl x install
  echo "[dev-env] waiting for cert-manager components available ..."
  kubectl wait --timeout=30s --for=condition=available deployment/cert-manager -n cert-manager
  echo "[dev-env] getting validation webhook config ..."
  kubectl get validatingwebhookconfigurations cert-manager-webhook -ojson | jq '.webhooks[].clientConfig'
  echo "[dev-env] getting cert-manager endpoints ..."
  kubectl get endpoints -n cert-manager cert-manager-webhook
  ./cmctl check api -n cert-manager --wait=2m
fi

echo "[dev-env] running helm chart e2e tests..."
kind get kubeconfig --internal --name $KIND_CLUSTER_NAME > $CT_CONFIG
docker run \
    --rm \
    --interactive \
    --network kind \
    --name ct \
    --volume "${CT_CONFIG}":/root/.kube/config \
    --volume "${CURDIR}":/workdir \
    --workdir /workdir \
    ${CT_IMAGE} ct install \
        --charts charts/ingress-nginx \
        --helm-extra-set-args "${HELM_EXTRA_SET_ARGS}" \
        --helm-extra-args "${HELM_EXTRA_ARGS}"
