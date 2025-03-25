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

# import functions
source "${PWD}/test/smoke/functions.sh"

# generate unique group name
export NODE_GROUP_NAME="gitlab-ingress-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12; echo)"
echo "[test-env] random node group name: ${NODE_GROUP_NAME}..."

# check if all mandatory vars was defined
check_mandatory_vars

KIND_LOG_LEVEL="1"

if ! [ -z $DEBUG ]; then
  set -x
  KIND_LOG_LEVEL="6"
fi

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=${TAG:=1.0.0-dev}
export ARCH=${ARCH:-amd64}

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

export WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
export WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-true}"
export SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
export SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"

K8S_VERSION=${K8S_VERSION:-v1.25.8}


# This will prevent the secret for index.docker.io from being used if the DOCKERHUB_USER is not set.
DOCKERHUB_REGISTRY_SERVER="https://index.docker.io/v1/"

if [ "${DOCKERHUB_USER:-false}" = "false" ]; then
  DOCKERHUB_REGISTRY_SERVER="fake_docker_registry_server"
fi

DOCKERHUB_SECRET_NAME="dockerhub-secret"
CI_REGISTRY_SECRET_NAME="ci-registry-secret"
DOCKERHUB_USER="${DOCKERHUB_USER:-fake_user}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-fake_password}"

set -o errexit
set -o nounset
set -o pipefail

trap cleanup EXIT ERR

[[ "${CI:-}" == "true" ]] && unset KUBERNETES_SERVICE_HOST

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
      --retain \
      --image "kindest/node:${K8S_VERSION}" \
      --config=<(cat << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000
        hostPort: 8080
        protocol: TCP
    extraMounts:
      - hostPath: "${CURDIR}/allure_report"
        containerPath: /allure_report
EOF
)

    echo "Kubernetes cluster:"
    kubectl get nodes -o wide
  fi
fi

# create docker-registry secret
echo "[test-env] creating secret docker-registry ..."
kubectl create secret docker-registry ${DOCKERHUB_SECRET_NAME} \
    --docker-server=${DOCKERHUB_REGISTRY_SERVER} \
    --docker-username="${DOCKERHUB_USER}" \
    --docker-password="${DOCKERHUB_PASSWORD}" \
    --docker-email=docker-pull@unexists.unexists || true

if [ "${SKIP_IMAGE_CREATION:-false}" = "false" ]; then
  echo "[test-env] building controller image..."
  make -C "${DIR}"/../../ clean-image build image
fi

# If this variable is set to 'true' we use public images instead local build.
if [ "${SKIP_IMAGE_LOADING:-false}" = "false" ]; then
  echo "[test-env] copying ${REGISTRY}/ingress-controller:${TAG} image to cluster..."
  kind load docker-image --name="${KIND_CLUSTER_NAME}" "${REGISTRY}/ingress-controller:${TAG}"
else
  TAG=$(cat "${CURDIR}/TAG")
  export TAG
fi


trap describe_pods_on_exit ERR

echo "[test-env] installing Helm chart using TAG=${TAG} ..."
cat << EOF | helm upgrade --install ingress-nginx "${DIR}/../../charts/ingress-nginx" --wait --values -
fullnameOverride: wallarm-ingress
imagePullSecrets:
  - name: ${DOCKERHUB_SECRET_NAME}
controller:
  wallarm:
    enabled: true
    token: ${WALLARM_API_TOKEN}
    apiHost: ${WALLARM_API_HOST}
    apiCaVerify: ${WALLARM_API_CA_VERIFY}
    nodeGroup: ${NODE_GROUP_NAME}
    fallback: "off"
    wcli:
      commands:
        detectCredStuffing:
          logLevel: DEBUG
        syncNode:
          logLevel: DEBUG
        syncIpLists:
          logLevel: DEBUG
  image:
    repository: ${REGISTRY}/ingress-controller
    tag: ${TAG}

  config:
    worker-processes: "1"
    enable-real-ip: true
    allow-snippet-annotations: true
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

kubectl wait --for=condition=Ready pods --all --timeout=120s

# ToDo: Add a readiness check for the webhook port controller to be ready
sleep 15

echo "[test-env] deploying test workload ..."
kubectl apply -f "${DIR}"/workload.yaml
kubectl wait --for=condition=Ready pods --all --timeout=60s

trap - ERR

echo "[test-env] running smoke tests suite ..."
make -C "${DIR}"/../../ smoke-test
