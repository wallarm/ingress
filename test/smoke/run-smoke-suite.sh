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
PYTEST_ARGS=$(echo "${PYTEST_ARGS:---allure-features=Node --last-failed}" | xargs)
PYTEST_WORKERS="${PYTEST_WORKERS:-20}"
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
    echo "###### List directory /opt/wallarm/etc/wallarm"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/etc/wallarm && cat /opt/wallarm/etc/wallarm/node.yaml" || true
    echo "###### List directory /var/lib/nginx/wallarm"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/var/lib/nginx/wallarm && ls -laht /opt/wallarm/var/lib/nginx/wallarm/shm" || true
    echo "###### List directory /opt/wallarm/var/lib/wallarm-acl"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/var/lib/wallarm-acl" || true
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
NODE_UUID=$(kubectl exec "${POD}" -c controller -- cat /opt/wallarm/etc/wallarm/node.yaml | grep uuid | awk '{print $2}')
echo "UUID: ${NODE_UUID}"

echo "Deploying pytest pod ..."

POD_CONFIG=$(cat << EOF
apiVersion: v1
kind: Pod
metadata:
  name: pytest
spec:
  terminationGracePeriodSeconds: 0
  restartPolicy: Never
  imagePullSecrets:
    - name: "${SMOKE_IMAGE_PULL_SECRET_NAME}"
  containers:
  - command:
    - sleep
    - infinity
    env:
    - name: NODE_BASE_URL
      value: "${NODE_BASE_URL}"
    - name: NODE_UUID
      value: "${NODE_UUID}"
    - name: WALLARM_API_HOST
      value: "${WALLARM_API_HOST}"
    - name: API_CA_VERIFY
      value: "${WALLARM_API_CA_VERIFY}"
    - name: CLIENT_ID
      value: "${CLIENT_ID}"
    - name: USER_UUID
      value: "${USER_UUID}"
    - name: USER_SECRET
      value: "${USER_SECRET}"
    - name: HOSTNAME_OLD_NODE
      value: "${HOSTNAME_OLD_NODE}"
    image: "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"
    imagePullPolicy: IfNotPresent
    name: pytest
EOF
)

if [ "${ALLURE_GENERATE_REPORT:-false}" = "true" ]; then
POD_CONFIG+=$(cat << EOF

    volumeMounts:
    - mountPath: /tests/_out/allure_report
      name: allure-report
      readOnly: false
  volumes:
  - name: allure-report
    hostPath:
      path: /allure_report
      type: DirectoryOrCreate
EOF
)
fi

echo "${POD_CONFIG}" | kubectl apply -f -

echo "Getting logs ..."
kubectl wait --for=condition=Ready pods --all --timeout=600s

echo "Run smoke tests ..."
trap get_logs_and_fail ERR

ENV_VARS=""
if [ "${ALLURE_UPLOAD_REPORT:-false}" = "true" ]; then
  export ALLURE_ENDPOINT="${ALLURE_ENDPOINT:-https://allure.wallarm.com}"
  export ALLURE_PROJECT_ID="${ALLURE_PROJECT_ID:-24}"
  export ALLURE_TOKEN="${ALLURE_TOKEN:-${ALLURE_SERVER_TOKEN}}"
  export ALLURE_LAUNCH_NAME="${WORKFLOW_RUN:-local}-${WORKFLOW_NAME:-local}-${JOB_NAME:-local}"
  export ALLURE_RESULTS="/tests/_out/allure_report"
  RUN_TESTS="allurectl watch -- pytest"
  ENV_VARS=(
    "env"
    "ALLURE_ENDPOINT=$ALLURE_ENDPOINT"
    "ALLURE_PROJECT_ID=$ALLURE_PROJECT_ID"
    "ALLURE_TOKEN=$ALLURE_TOKEN"
    "ALLURE_LAUNCH_NAME=$ALLURE_LAUNCH_NAME"
    "ALLURE_RESULTS=$ALLURE_RESULTS"
  )
  ENV_VARS_STR="${ENV_VARS[*]}"
else
  RUN_TESTS="pytest"
fi

EXEC_CMD="$ENV_VARS_STR $RUN_TESTS -n ${PYTEST_WORKERS} ${PYTEST_ARGS}"

echo "Executing command: kubectl exec pytest ${EXEC_ARGS} -- $EXEC_CMD"
# shellcheck disable=SC2086
kubectl exec pytest ${EXEC_ARGS} -- $EXEC_CMD