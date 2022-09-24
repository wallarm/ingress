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

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=1.0.0-dev
export ARCH=${ARCH:-amd64}

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"
export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}

export WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
export SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
export SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"

K8S_VERSION=${K8S_VERSION:-v1.24.2}

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

trap cleanup EXIT ERR

declare -a mandatory
mandatory=(
  SMOKE_IMAGE_NAME
  SMOKE_IMAGE_TAG
  WALLARM_API_HOST
  WALLARM_API_TOKEN
)

missing=false
for var in "${mandatory[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Environment variable $var must be set"
    missing=true
  fi
done

if [ "$missing" = true ]; then
  exit 1
fi

if ! command -v kind --version &> /dev/null; then
  echo "kind is not installed. Use the package manager or visit the official site https://kind.sigs.k8s.io/"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  if kind get clusters | grep -q "${KIND_CLUSTER_NAME}"; then
    echo "[test-env] Kubernetes cluster ${KIND_CLUSTER_NAME} already exists. Using existing cluster ..."
  else
    echo "[test-env] creating Kubernetes cluster with kind"
    kind create cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME} \
      --config ${DIR}/kind.yaml \
      --retain \
      --image "kindest/node:${K8S_VERSION}"

    echo "Kubernetes cluster:"
    kubectl get nodes -o wide
  fi
fi

if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  echo "[test-env] building controller image..."
  make -C "${DIR}"/../../ clean-image build image
fi

echo "[test-env] copying ${REGISTRY}/ingress-controller:${TAG} image to cluster..."
kind load docker-image --name="${KIND_CLUSTER_NAME}" "${REGISTRY}/ingress-controller:${TAG}"

echo "[test-env] copying helper images to cluster..."
${DIR}/../../build/load-images.sh

echo "[test-env] copying test image to cluster ..."
docker pull --quiet "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"
kind load docker-image --name="${KIND_CLUSTER_NAME}" "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"

echo "[test-env] installing Helm chart ..."
cat << EOF | helm upgrade --install ingress-nginx "${DIR}/../../charts/ingress-nginx" --wait --values -
fullnameOverride: wallarm-ingress
controller:
  wallarm:
    enabled: true
    token: ${WALLARM_API_TOKEN}
    apiHost: ${WALLARM_API_HOST}
    fallback: "off"
  image:
    repository: ${REGISTRY}/ingress-controller
    tag: ${TAG}
    digest:
  imagePullPolicy: Never
  config:
    worker-processes: "1"
    enable-real-ip: true
    forwarded-for-header: X-Real-IP
    proxy-real-ip-cidr: 0.0.0.0/0
  readinessProbe:
    initialDelaySeconds: 3
    periodSeconds: 1
  livenessProbe:
    initialDelaySeconds: 3
    periodSeconds: 1
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  terminationGracePeriodSeconds: 0
  service:
    type: NodePort
    nodePorts:
      http: 30000
EOF

kubectl wait --for=condition=Ready pods --all --timeout=100s

echo "[test-env] deploying test workload ..."
kubectl apply -f "${DIR}"/workload.yaml
kubectl wait --for=condition=Ready pods --all --timeout=60s

echo "[test-env] running smoke tests suite ..."
make -C "${DIR}"/../../ smoke-test