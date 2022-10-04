#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

KIND_WORKERS="${KIND_WORKERS:-${KIND_CLUSTER_NAME}-control-plane}"

HELPER_TAG="${HELPER_TAG:-$(cat "${DIR}"/../TAG)}"

HELPER_IMAGES=(
  ingress-ruby
  ingress-tarantool
  ingress-python
  ingress-collectd
)

echo "Kind cluster name: ${KIND_CLUSTER_NAME}"
echo "Kind workers: ${KIND_WORKERS}"
for ITEM in "${HELPER_IMAGES[@]}"; do
  IMAGE="${REGISTRY}/${ITEM}"
  docker pull --quiet "${IMAGE}:${HELPER_TAG}"
  docker tag "${IMAGE}:${HELPER_TAG}" "${IMAGE}:${TAG}"
  kind load docker-image --name="${KIND_CLUSTER_NAME}" --nodes="${KIND_WORKERS}" "${IMAGE}:${TAG}"
done
