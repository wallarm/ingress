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
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
  else
    rm -f ct.sh
    rm -rf ct_previous_revision*
  fi
}

trap cleanup EXIT

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-nginx-dev}

if ! command -v kind --version &> /dev/null; then
  echo "kind is not installed. Use the package manager or visit the official site https://kind.sigs.k8s.io/"
  exit 1
fi

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=1.0.0-dev
export ARCH=${ARCH:-amd64}

# The image for chart testing tool
CT_IMAGE="quay.io/helmpack/chart-testing:v3.7.1-amd64"
CT_NAMESPACE="ct"

# Handle the case when we run chart testing with '--upgrade' option
if [[ "${CT_MODE:-}" == "upgrade" ]]; then
  CT_ARGS="--target-branch main --remote origin --upgrade --skip-missing-values"
else
  CT_ARGS="--charts charts/ingress-nginx"
fi

HELM_EXTRA_SET_ARGS="\
 --set controller.wallarm.apiHost=${WALLARM_API_HOST:-api.wallarm.com} \
 --set controller.wallarm.token=${WALLARM_API_TOKEN} \
 --set controller.wallarm.enabled=true \
 --set controller.image.repository=wallarm/ingress-controller \
 --set controller.image.tag=1.0.0-dev \
 --set controller.terminationGracePeriodSeconds=0 \
 --set fullnameOverride=wallarm-ingress ${HELM_EXTRA_SET_ARGS:-}"

SECRET_NAME="wallarm-api-token"
SECRET_KEY="token"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

if [ "${SKIP_CLUSTER_CREATION:-false}" = "false" ]; then
  echo "[dev-env] creating Kubernetes cluster with kind"

  export K8S_VERSION=${K8S_VERSION:-v1.25.2@sha256:1f0cee2282f43150b52dc7933183ed96abdcfc8d293f30ec07082495874876f1}

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
  make -C ${DIR}/../../ clean-image build image
fi
  

export KIND_WORKERS=$(kind get nodes --name="${KIND_CLUSTER_NAME}" | grep 'worker' | awk '{printf (NR>1?",":"") $1}')

echo "[dev-env] copying docker images to cluster..."
kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes="${KIND_WORKERS}" wallarm/ingress-controller:${TAG}

echo "[dev-env] copying helper images to cluster..."
"${CURDIR}"/build/load-images.sh

if ! kubectl get namespace ${CT_NAMESPACE} &> /dev/null; then
  echo "[dev-env] creating namespace for chart testing..."
  kubectl create namespace ${CT_NAMESPACE}
fi

if ! kubectl -n ${CT_NAMESPACE} get secret "${SECRET_NAME}" &> /dev/null; then
  echo "[dev-env] creating secret ${SECRET_NAME}..."
  kubectl -n ${CT_NAMESPACE} create secret generic "${SECRET_NAME}" --from-literal="${SECRET_KEY}"="${WALLARM_API_TOKEN}"
fi

cat <<EOF > ct.sh
#!/bin/bash
set -e
git rev-parse --is-inside-work-tree &> /dev/null || git config --global --add safe.directory /workdir
exec ct install \
 --namespace ${CT_NAMESPACE} \
 --helm-extra-set-args "${HELM_EXTRA_SET_ARGS}" \
 --helm-extra-args "--timeout 180s" \
 ${CT_ARGS:-} \
 --debug
EOF
chmod +x ct.sh

echo "[dev-env] running helm chart e2e tests..."
docker run \
    --rm \
    --interactive \
    --network host \
    --name ct \
    --volume "${KUBECONFIG}:/root/.kube/config" \
    --volume "${CURDIR}:/workdir" \
    --workdir /workdir \
    --entrypoint /workdir/ct.sh \
    ${CT_IMAGE}