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

export DOCKER_CLI_EXPERIMENTAL=enabled
export K8S_VERSION=${K8S_VERSION:-v1.24.2}
export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

set -o errexit
set -o nounset
set -o pipefail

cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi

  kind delete cluster \
    --verbosity=${KIND_LOG_LEVEL} \
    --name ${KIND_CLUSTER_NAME}
}

#trap cleanup EXIT

declare -a mandatory
mandatory=(
  WALLARM_API_HOST
  WALLARM_API_TOKEN
  SMOKE_IMAGE_NAME
  SMOKE_IMAGE_TAG
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
  make -C ${DIR}/../../ clean-image build image
fi

echo "[test-env] copying ${REGISTRY}/ingress-controller:${TAG} image to cluster..."
kind load docker-image --name="${KIND_CLUSTER_NAME}" ${REGISTRY}/ingress-controller:${TAG}

echo "[test-env] copying helper images to cluster..."
helper_tag=$(cat "${DIR}"/../../TAG)
helper_images=(
  wallarm/ingress-ruby
  wallarm/ingress-tarantool
  wallarm/ingress-python
  wallarm/ingress-collectd
)
for image in "${helper_images[@]}"; do
  docker pull --quiet "${image}:${helper_tag}"
  docker tag "${image}:${helper_tag}" "${image}:${TAG}"
  kind load docker-image --quiet --name="${KIND_CLUSTER_NAME}" "${image}:${TAG}"
done

echo "[test-env] copying test image to cluster ..."
docker pull --quiet "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"
kind load docker-image --name="${KIND_CLUSTER_NAME}" "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"

echo "[test-env] installing Helm chart ..."
kubectl create namespace wallarm-ingress &> /dev/null || true

cat << EOF | helm upgrade --install ingress-nginx "${DIR}/../../charts/ingress-nginx" --namespace=wallarm-ingress --wait --values -
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
  config:
    worker-processes: "1"
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

kubectl wait -n wallarm-ingress --for=condition=Ready pods --all --timeout=60s

echo "[test-env] deploying test workload ..."
set -x
KUBECTL_ARGS="--dry-run=client --save-config -o yaml"

kubectl create deployment httpbin \
        --image kennethreitz/httpbin \
        --port 80 \
        --replicas 1 \
        ${KUBECTL_ARGS} | kubectl apply -f -
kubectl expose deployment httpbin \
        --port 80 \
        ${KUBECTL_ARGS} | kubectl apply -f -
kubectl create ingress httpbin \
        --class nginx \
        --rule "/*=httpbin:80" \
        --annotation="nginx.ingress.kubernetes.io/wallarm-mode=block" \
        ${KUBECTL_ARGS} | kubectl apply -f -

echo "[test-env] running smoke tests suite ..."
make -C ${DIR}/../../ smoke-test
