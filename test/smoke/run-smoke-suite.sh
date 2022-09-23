#!/bin/bash

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

set -o errexit
set -o nounset
set -o pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-ingress-smoke-test}"

SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"

# Pytest related variables
WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-True}"
WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
NODE_BASE_URL="${NODE_BASE_URL:-http://wallarm-ingress-controller.default.svc}"
PYTEST_ARGS="${PYTEST_ARGS:---allure-features=Node}"
PYTEST_WORKERS="${PYTEST_WORKERS:-10}"
#TODO We need it here just to don't let test fail. Remove this variable when test will be fixed.
HOSTNAME_OLD_NODE="smoke-tests-old-node"

declare -a mandatory
mandatory=(
  CLIENT_ID
  USER_UUID
  USER_SECRET
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

echo "Retrieving Wallarm Node UUID ..."
POD=$(kubectl get pod -l "app.kubernetes.io/component=controller" -o=name | cut -d/ -f 2)
NODE_UUID=$(kubectl logs "${POD}" -c addnode | grep 'Registered new instance' | awk -F 'instance ' '{print $2}')
echo "UUID: ${NODE_UUID}"

echo "Run smoke tests ..."
kubectl run pytest \
  --rm --tty --stdin --quiet \
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
