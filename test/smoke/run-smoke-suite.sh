#!/bin/bash

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

set -o errexit
set -o nounset
set -o pipefail

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

# Variable required for smoke tests report
export ALLURE_UPLOAD_REPORT="${ALLURE_UPLOAD_REPORT:-false}"
export ALLURE_GENERATE_REPORT="${ALLURE_GENERATE_REPORT:-false}"

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
PYTEST_WORKERS="${PYTEST_WORKERS:-20}"
#TODO We need it here just to don't let test fail. Remove this variable when test will be fixed.
HOSTNAME_OLD_NODE="smoke-tests-old-node"

function clear_allure_report() {
  [[ "$ALLURE_GENERATE_REPORT" == false && -d "allure_report" ]] && rm -rf allure_report/* 2>/dev/null || true
}

function get_logs_and_fail() {
    get_logs
    clear_allure_report
    exit 1
}

function get_logs() {
    echo "###### Init container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c addnode --tail=-1
    echo "###### Controller container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c controller --tail=-1
    echo "###### Cron container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c cron --tail=-1
    echo "###### API-WF container logs ######"
    kubectl logs -l "app.kubernetes.io/component=controller" -c api-firewall --tail=-1 || true
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
  USER_TOKEN
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
if [[ -z "${NODE_UUID}" ]]; then
  echo "Failed to retrieve Wallarm Node UUID"
  get_logs_and_fail
fi
echo "UUID: ${NODE_UUID}"

RAND_NUM="${RANDOM}${RANDOM}${RANDOM}"
RAND_NUM=${RAND_NUM:0:10}

echo "Deploying pytest pod ..."

kubectl apply -f - << EOF
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
  - command: [sleep, infinity]
    env:
    - {name: NODE_BASE_URL, value: "${NODE_BASE_URL}"}
    - {name: NODE_UUID, value: "${NODE_UUID}"}
    - {name: WALLARM_API_HOST, value: "${WALLARM_API_HOST}"}
    - {name: WALLARM_API_PRESET, value: "${WALLARM_API_PRESET:-eu1}"}
    - {name: API_CA_VERIFY, value: "${WALLARM_API_CA_VERIFY}"}
    - {name: CLIENT_ID, value: "${CLIENT_ID}"}
    - {name: USER_TOKEN, value: "${USER_TOKEN}"}
    - {name: HOSTNAME_OLD_NODE, value: "${HOSTNAME_OLD_NODE}"}
    - {name: ALLURE_ENVIRONMENT_K8S, value: "${ALLURE_ENVIRONMENT_K8S:-}"}
    - {name: ALLURE_ENVIRONMENT_ARCH, value: "${ALLURE_ENVIRONMENT_ARCH:-}"}
    - {name: ALLURE_ENDPOINT, value: "${ALLURE_ENDPOINT:-}"}
    - {name: ALLURE_PROJECT_ID, value: "${ALLURE_PROJECT_ID:-}"}
    - {name: ALLURE_TOKEN, value: "${ALLURE_TOKEN:-}"}
    - {name: ALLURE_RESULTS, value: "${ALLURE_RESULTS:-/tests/_out/allure_report}"}
    - {name: TEST_RC, value: "${TEST_RC:-false}"}
    - name: ALLURE_LAUNCH_TAGS
      value: >
        USER:${GITHUB_ACTOR:-local},
        WORKFLOW:${GITHUB_WORKFLOW:-local},
        RUN_ID:${GITHUB_RUN_ID:-local},
        BRANCH:${GITHUB_REF_NAME:-local},
        JOB:${GITHUB_JOB:-local},
        K8S:${ALLURE_ENVIRONMENT_K8S:-},
        ARCH:${ALLURE_ENVIRONMENT_ARCH:-}
    - name: ALLURE_LAUNCH_NAME
      value: >
        ${GITHUB_WORKFLOW:-local}-${GITHUB_RUN_ID:-local}-${GITHUB_JOB:-local}-
        ${ALLURE_ENVIRONMENT_K8S:-}-${ALLURE_ENVIRONMENT_ARCH:-}
    image: "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"
    imagePullPolicy: IfNotPresent
    name: pytest
    volumeMounts:
    - {mountPath: /tests/_out/allure_report, name: allure-report, readOnly: false}
  volumes:
  - name: allure-report
    hostPath: {path: /allure_report, type: DirectoryOrCreate}
EOF

echo "Waiting for all pods ready ..."
kubectl wait --for=condition=Ready pods --all --timeout=300s

echo "Run smoke tests ..."
GITHUB_VARS=$(env | awk -F '=' '/^GITHUB_/ {vars = vars $1 "=" $2 " ";} END {print vars}')
RUN_TESTS=$([ "$ALLURE_UPLOAD_REPORT" = "true" ] && echo "allurectl watch --job-uid ${RAND_NUM} -- pytest" || echo "pytest")

EXEC_CMD="env $GITHUB_VARS $RUN_TESTS -n ${PYTEST_WORKERS} ${PYTEST_ARGS}"
# shellcheck disable=SC2086
kubectl exec pytest ${EXEC_ARGS} -- ${EXEC_CMD} || get_logs_and_fail
clear_allure_report