# This file used for import in other files

RED='\033[0;31m'
NC='\033[0m'

function check_mandatory_vars() {

    declare -a mandatory
    declare -a allure_mandatory

    mandatory=(
      WALLARM_API_TOKEN
      WALLARM_API_HOST
      WALLARM_API_PRESET
      CLIENT_ID
      USER_TOKEN
      WEBHOOK_API_KEY
      WEBHOOK_UUID
      SMOKE_REGISTRY_TOKEN
      SMOKE_REGISTRY_SECRET
      NODE_GROUP_NAME
    )

    env_list=""

    for var in "${mandatory[@]}"; do
      if [[ -z "${!var:-}" ]]; then
        env_list+=" $var"
      fi
    done

    if [[ "${ALLURE_UPLOAD_REPORT:-false}" == "true" ]]; then

      allure_mandatory=(
        ALLURE_TOKEN
        ALLURE_ENVIRONMENT_ARCH
        ALLURE_PROJECT_ID
        ALLURE_GENERATE_REPORT
        ALLURE_ENVIRONMENT_K8S
      )

      for var in "${allure_mandatory[@]}"; do
        if [[ -z "${!var:-}" ]]; then
          env_list+=" $var"
        fi
      done
    fi

    if [[ -n "$env_list" ]]; then
      for var in ${env_list}; do
        echo -e "${RED}Environment variable $var must be set${NC}"
      done
      exit 1
    fi

}

function cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME}
  fi
}

function describe_pods_on_exit() {
    controller_label="app.kubernetes.io/component=controller"
    tarantool_label="app.kubernetes.io/component=controller-wallarm-tarantool"
    workload_label="app=workload"

    echo "#################### Describe controller POD ####################"
    kubectl describe pod -l $controller_label
    echo "#################### Describe Tarantool POD ####################"
    kubectl describe pod -l $tarantool_label
    echo "#################### Describe workload POD ####################"
    kubectl describe pod -l $workload_label
}

function clean_allure_report() {
  [[ "$ALLURE_GENERATE_REPORT" == false && -d "allure_report" ]] && rm -rf allure_report/* 2>/dev/null || true
}

function get_logs_and_fail() {
    get_logs
    extra_debug_logs
    clean_allure_report
    exit 1
}

function get_logs() {
    echo "#################################"
    echo "###### Init container logs ######"
    echo "#################################"
    kubectl logs -l "app.kubernetes.io/component=controller" -c addnode --tail=-1
    echo -e "#################################\n"

    echo "#######################################"
    echo "###### Controller container logs ######"
    echo "#######################################"
    kubectl logs -l "app.kubernetes.io/component=controller" -c controller --tail=-1
    echo -e "#######################################\n"

    echo "#################################"
    echo "###### Cron container logs ######"
    echo "#################################"
    kubectl logs -l "app.kubernetes.io/component=controller" -c cron --tail=-1
    echo -e "#################################\n"

    echo "###################################"
    echo "###### API-WF container logs ######"
    echo "###################################"
    kubectl logs -l "app.kubernetes.io/component=controller" -c api-firewall --tail=-1 || true
    echo -e "####################################\n"

    echo "####################################################"
    echo "###### List directory /opt/wallarm/etc/wallarm #####"
    echo "####################################################"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/etc/wallarm && cat /opt/wallarm/etc/wallarm/node.yaml" || true
    echo -e "#####################################################\n"

    echo "############################################"
    echo "###### List directory /var/lib/nginx/wallarm"
    echo "############################################"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/var/lib/nginx/wallarm && ls -laht /opt/wallarm/var/lib/nginx/wallarm/shm" || true
    echo -e "############################################\n"

    echo "############################################################"
    echo "###### List directory /opt/wallarm/var/lib/wallarm-acl #####"
    echo "############################################################"
    kubectl exec "${POD}" -c controller -- sh -c "ls -laht /opt/wallarm/var/lib/wallarm-acl" || true
    echo -e "############################################################\n"

    echo "##################################################"
    echo "###### TARANTOOL Pod - Cron container logs  ######"
    echo "##################################################"
    kubectl logs -l "app.kubernetes.io/component=controller-wallarm-tarantool" -c cron --tail=-1
    echo -e "##################################################\n"

    echo "######################################################"
    echo "###### TARANTOOL Pod - Tarantool container logs ######"
    echo "######################################################"
    kubectl logs -l "app.kubernetes.io/component=controller-wallarm-tarantool" -c tarantool --tail=-1
    echo -e "######################################################\n"
}

function extra_debug_logs {
  echo "############################################"
  echo "###### Extra cluster debug info ############"
  echo "############################################"

  echo "Grepping cluster OOMKilled events..."
  kubectl get events -A | grep -i OOMKill || true

  echo "Displaying pods state in default namespace..."
  kubectl get pods

}


