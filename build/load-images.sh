#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

KIND_WORKERS="${KIND_WORKERS:-${KIND_CLUSTER_NAME}-control-plane}"

HELPER_TAG="${HELPER_TAG:-$(cat "${DIR}"/../TAG)}"
HELPER_REGISTRY="${HELPER_REGISTRY:-docker.io/wallarm}"

HELPER_IMAGES=(
  ingress-ruby
  ingress-tarantool
  ingress-python
  ingress-collectd
)

echo "Kind cluster name: ${KIND_CLUSTER_NAME}"
echo "Kind workers: ${KIND_WORKERS}"
echo "Helper images registry: ${HELPER_REGISTRY}"
for IMAGE in "${HELPER_IMAGES[@]}"; do
  docker pull "${HELPER_REGISTRY}/${IMAGE}:${HELPER_TAG}"
  docker tag "${HELPER_REGISTRY}/${IMAGE}:${HELPER_TAG}" "${REGISTRY}/${IMAGE}:${TAG}"
  kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes="${KIND_WORKERS}" "${REGISTRY}/${IMAGE}:${TAG}"
done
