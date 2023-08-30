#!/bin/bash

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

set -o errexit
set -o nounset
set -o pipefail

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"


# Variables required for pulling Docker image with pytest
SMOKE_REGISTRY_NAME="${SMOKE_REGISTRY_NAME:-dkr.wallarm.com}"
SMOKE_IMAGE_PULL_SECRET_NAME="pytest-registry-creds"

SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"

# Pytest related variables
WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-true}"
WALLARM_API_HOST="${WALLARM_API_HOST:-api.wallarm.com}"
NODE_BASE_URL="${NODE_BASE_URL:-http://wallarm-ingress-controller.default.svc}"
PYTEST_ARGS=$(echo "${PYTEST_ARGS:---allure-features=Node}" | xargs)
PYTEST_WORKERS="${PYTEST_WORKERS:-10}"
#TODO We need it here just to don't let test fail. Remove this variable when test will be fixed.
HOSTNAME_OLD_NODE="smoke-tests-old-node"

function get_logs_and_fail() {
    get_logs
    exit 1
}

function get_logs() {
    echo "###### Init container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c addnode --tail=-1
    echo "###### Controller container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c controller --tail=-1
    echo "###### Cron container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c cron --tail=-1
    echo "###### List directory /etc/wallarm"
    kubectl exec "${POD}" -c controller -- sh -c "ls -lah /etc/wallarm && cat /etc/wallarm/node.yaml"
    echo "###### List directory /var/lib/nginx/wallarm"
    kubectl exec "${POD}" -c controller -- sh -c "ls -lah /var/lib/nginx/wallarm && ls -lah /var/lib/nginx/wallarm/shm"
}

declare -a mandatory
mandatory=(
  CLIENT_ID
  USER_UUID
  USER_SECRET
  SMOKE_REGISTRY_TOKEN
  SMOKE_REGISTRY_SECRET
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

if [[ "${CI:-false}" == "false" ]]; then
  trap 'kubectl delete pod pytest --now  --ignore-not-found' EXIT ERR
  # Colorize pytest output if run locally
  EXEC_ARGS="--tty --stdin"
else
  EXEC_ARGS="--tty"
fi

if ! kubectl get secret "${SMOKE_IMAGE_PULL_SECRET_NAME}" &> /dev/null; then
  echo "Creating secret with pytest registry credentials ..."
  kubectl create secret docker-registry ${SMOKE_IMAGE_PULL_SECRET_NAME} \
    --docker-server="${SMOKE_REGISTRY_NAME}" \
    --docker-username="${SMOKE_REGISTRY_TOKEN}" \
    --docker-password="${SMOKE_REGISTRY_SECRET}" \
    --docker-email=docker-pull@unexists.unexists
fi

echo "Retrieving Wallarm Node UUID ..."
POD=$(kubectl get pod -l "app.kubernetes.io/component=controller" -o=name | cut -d/ -f 2)
NODE_UUID=$(kubectl exec "${POD}" -c controller -- cat /etc/wallarm/node.yaml | grep uuid | awk '{print $2}')
echo "UUID: ${NODE_UUID}"

echo "Deploying pytest pod ..."
kubectl run pytest \
  --env="NODE_BASE_URL=${NODE_BASE_URL}" \
  --env="NODE_UUID=${NODE_UUID}" \
  --env="WALLARM_API_HOST=${WALLARM_API_HOST}" \
  --env="API_CA_VERIFY=${WALLARM_API_CA_VERIFY}" \
  --env="CLIENT_ID=${CLIENT_ID}" \
  --env="USER_UUID=${USER_UUID}" \
  --env="USER_SECRET=${USER_SECRET}" \
  --env="HOSTNAME_OLD_NODE=${HOSTNAME_OLD_NODE}" \
  --image="${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}" \
  --image-pull-policy=IfNotPresent \
  --pod-running-timeout=1m0s \
  --restart=Never \
  --overrides='{"apiVersion": "v1", "spec":{"terminationGracePeriodSeconds": 0, "imagePullSecrets": [{"name": "'"${SMOKE_IMAGE_PULL_SECRET_NAME}"'"}]}}' \
  --command -- sleep infinity

kubectl wait --for=condition=Ready pods --all --timeout=60s

echo "Getting logs ..."
get_logs

echo "Run smoke tests ..."
trap get_logs_and_fail ERR
kubectl exec pytest ${EXEC_ARGS} -- pytest -n ${PYTEST_WORKERS} ${PYTEST_ARGS}