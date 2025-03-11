#!/bin/bash

if [[ -n "${DEBUG}" ]]; then
  set -x
fi

function wait_for_node() {
  POD=$(kubectl get pod -l "app.kubernetes.io/component=controller" -o=name | cut -d/ -f 2)
  WAIT_TIMEOUT_SECONDS=60

  for i in $(seq 1 $WAIT_TIMEOUT_SECONDS); do
      printf '.'
      
      status="$(kubectl exec ${POD} -- curl -I -o /dev/null -w %{http_code} 127.0.0.1?sqli=union+select+1 || true)"
      if [[ "$status" -eq 403 ]]; then
          # If the attack was blocked, then wallarm-node started and enabled protection
          printf '\nINFO: wallarm-node started OK and enabled protection after %s seconds\n' "$i"
          return 0
      fi
      sleep 1

  done

  printf '\n'
  printf 'ERROR: wallarm-node failed to start within %s seconds\n' "$WAIT_TIMEOUT_SECONDS"
  return 1

}

set -o errexit
set -o nounset
set -o pipefail

# import functions
source "${PWD}/test/smoke/functions.sh"

# check if all mandatory vars was defined
check_mandatory_vars

export KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-ingress-smoke-test}
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-config-$KIND_CLUSTER_NAME}"

# Variables required for pulling Docker image with pytest
SMOKE_REGISTRY_NAME="${SMOKE_REGISTRY_NAME:-dkr.wallarm.com}"
SMOKE_IMAGE_PULL_SECRET_NAME="pytest-registry-creds"

SMOKE_IMAGE_NAME="${SMOKE_IMAGE_NAME:-dkr.wallarm.com/tests/smoke-tests}"
SMOKE_IMAGE_TAG="${SMOKE_IMAGE_TAG:-latest}"

# Allure related variables
ALLURE_ENDPOINT="${ALLURE_ENDPOINT:-https://allure.wallarm.com}"
ALLURE_PROJECT_ID=${ALLURE_PROJECT_ID:-0}
ALLURE_RESULTS="${ALLURE_RESULTS:-/tests/_out/allure_report}"
ALLURE_UPLOAD_REPORT="${ALLURE_UPLOAD_REPORT:-false}"
ALLURE_GENERATE_REPORT="${ALLURE_GENERATE_REPORT:-false}"

# Pytest related variables
CLIENT_ID="${CLIENT_ID}"
WALLARM_API_CA_VERIFY="${WALLARM_API_CA_VERIFY:-true}"
WALLARM_API_HOST="${WALLARM_API_HOST}"
WALLARM_API_PRESET="${WALLARM_API_PRESET}"
NODE_BASE_URL="${NODE_BASE_URL:-http://wallarm-ingress-controller.default.svc}"
PYTEST_PARAMS=$(echo "${PYTEST_PARAMS:---allure-features=Node}" | xargs)
PYTEST_PROCESSES="${PYTEST_PROCESSES:-10}"
#TODO We need it here just to don't let test fail. Remove this variable when test will be fixed.
HOSTNAME_OLD_NODE="smoke-tests-old-node"

NODE_VERSION=$(< "${CURDIR}/AIO_BASE" awk -F'[-.]' '{print $1"."$2"."$3}')
echo "[test-env] AiO Node version: ${NODE_VERSION}"

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

echo "[test-env] Deploying pytest pod ..."

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
    - {name: NODE_GROUP_NAME, value: "${NODE_GROUP_NAME}"}
    - {name: WALLARM_API_HOST, value: "${WALLARM_API_HOST}"}
    - {name: WALLARM_API_PRESET, value: "${WALLARM_API_PRESET}"}
    - {name: API_CA_VERIFY, value: "${WALLARM_API_CA_VERIFY}"}
    - {name: CLIENT_ID, value: "${CLIENT_ID}"}
    - {name: USER_TOKEN, value: "${USER_TOKEN}"}
    - {name: HOSTNAME_OLD_NODE, value: "${HOSTNAME_OLD_NODE}"}
    - {name: WEBHOOK_UUID, value: "${WEBHOOK_UUID}"}
    - {name: WEBHOOK_API_KEY, value: "${WEBHOOK_API_KEY}"}
    - {name: ALLURE_ENVIRONMENT_K8S, value: "${ALLURE_ENVIRONMENT_K8S:-}"}
    - {name: ALLURE_ENVIRONMENT_ARCH, value: "${ALLURE_ENVIRONMENT_ARCH:-}"}
    - {name: ALLURE_ENDPOINT, value: "${ALLURE_ENDPOINT}"}
    - {name: ALLURE_PROJECT_ID, value: "${ALLURE_PROJECT_ID}"}
    - {name: ALLURE_TOKEN, value: "${ALLURE_TOKEN:-}"}
    - {name: ALLURE_RESULTS, value: "${ALLURE_RESULTS}"}
    - {name: NODE_VERSION, value: "${NODE_VERSION:-}"}
    - {name: PYTEST_PARAMS, value: "${PYTEST_PARAMS}"}
    - {name: PYTEST_PROCESSES, value: "${PYTEST_PROCESSES}"}
    - {name: ALLURE_TESTPLAN_PATH, value: "./testplan.json"}
    - {name: RUN_TESTS_RC_FILE, value: "run_tests_rc"}
    - {name: DIST, value: "worksteal"}
    - name: ALLURE_LAUNCH_TAGS
      value: "USR:${GITLAB_USER_NAME}, SRC:${CI_PIPELINE_SOURCE}, GITLAB_REPO:${CI_PROJECT_NAME}"
    - name: ALLURE_LAUNCH_NAME
      value: >
        ${CI_COMMIT_REF_NAME} #${CI_COMMIT_SHORT_SHA} on ${WALLARM_API_PRESET} ${CI_PIPELINE_ID} 
        ${ALLURE_ENVIRONMENT_K8S}-${ALLURE_ENVIRONMENT_ARCH}
    image: "${SMOKE_IMAGE_NAME}:${SMOKE_IMAGE_TAG}"
    imagePullPolicy: IfNotPresent
    name: pytest
    volumeMounts:
    - {mountPath: /tests/_out/allure_report, name: allure-report, readOnly: false}
  volumes:
  - name: allure-report
    hostPath: {path: /allure_report, type: DirectoryOrCreate}
EOF

echo "[test-env] Waiting for all pods ready ..."
kubectl wait --for=condition=Ready pods --all --timeout=300s

wait_for_node || get_logs_and_fail

sleep 10 # wait node to export first attack

echo "[test-env] Run smoke tests ..."

GITLAB_VARS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && GITLAB_VARS+=("$line")
done < <(printenv | grep -E '^(GITLAB_|ALLURE_)')

EXEC_CMD=(
  env
  "${GITLAB_VARS[@]}"
  /usr/local/bin/test-entrypoint.sh
)

if [ "$ALLURE_UPLOAD_REPORT" = "true" ]; then
  EXEC_CMD+=(ci)
else
  EXEC_CMD+=(pytest ${PYTEST_PARAMS})
fi

# Execute with proper array handling
kubectl exec pytest "${EXEC_ARGS[@]}" -- "${EXEC_CMD[@]}" || get_logs_and_fail

extra_debug_logs
clean_allure_report
