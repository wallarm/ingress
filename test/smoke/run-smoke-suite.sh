#!/bin/bash

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

set -o errexit
set -o nounset
set -o pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-ingress-smoke-test}"

PYTEST_ARGS="${PYTEST_ARGS:-}"
PYTEST_WORKERS="${PYTEST_WORKERS:-10}"

if [[ -n "${PYTEST_ARGS}" ]]; then
  PYTEST_ARGS=$(echo "${PYTEST_ARGS}" | xargs)
fi

declare -a mandatory
mandatory=(
  NODE_BASE_URL
  WALLARM_API_HOST
  WALLARM_API_CA_VERIFY
  CLIENT_ID
  USER_UUID
  USER_SECRET
  HOSTNAME_OLD_NODE
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

echo "Retrieving Wallarm Node UUID from controller ..."
CONTROLLER_POD=$(kubectl get pod -n wallarm-ingress -l "app.kubernetes.io/component=controller" -o=name | cut -d/ -f 2)
NODE_UUID=$(kubectl logs -n wallarm-ingress "${CONTROLLER_POD}" -c addnode | grep 'Registered new instance' | awk -F 'instance ' '{print $2}')
echo "UUID: ${NODE_UUID}"

trap 'kubectl delete pod pytest --ignore-not-found=true' ERR EXIT

echo "Starting the smoke test pod..."
kubectl run pytest \
  --rm \
  --attach \
  --env="NODE_BASE_URL=${NODE_BASE_URL}" \
  --env="NODE_UUID=${NODE_UUID}" \
  --env="WALLARM_API_HOST=${WALLARM_API_HOST}" \
  --env="API_CA_VERIFY=${WALLARM_API_CA_VERIFY}" \
  --env="CLIENT_ID=${CLIENT_ID}" \
  --env="USER_UUID=${USER_UUID}" \
  --env="USER_SECRET=${USER_SECRET}" \
  --env="HOSTNAME_OLD_NODE=${HOSTNAME_OLD_NODE}" \
  --image="${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}" \
  --image-pull-policy=Never \
  --restart=Never \
  --overrides='{ "apiVersion": "v1", "spec":{"terminationGracePeriodSeconds": 0}}' \
  --command -- pytest -n ${PYTEST_WORKERS} ${PYTEST_ARGS}
