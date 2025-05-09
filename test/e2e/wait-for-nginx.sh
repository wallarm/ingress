#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
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

set -e
if ! [ -z $DEBUG ]; then
	set -x
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export NAMESPACE=$1
export NAMESPACE_OVERLAY=$2
export IS_CHROOT=$3
export ENABLE_VALIDATIONS=$4

echo "deploying NGINX Ingress controller in namespace $NAMESPACE"

function on_exit {
    local error_code="$?"

    test $error_code == 0 && return;

    echo "Obtaining ingress controller pod logs..."
    kubectl logs -l app.kubernetes.io/name=wallarm-ingress -n $NAMESPACE
}
trap on_exit EXIT

cat << EOF | kubectl apply --namespace=$NAMESPACE -f -
# Required for e2e tcp tests
kind: ConfigMap
apiVersion: v1
metadata:
  name: tcp-services
  namespace: $NAMESPACE

EOF

# Use the namespace overlay if it was requested
if [[ ! -z "$NAMESPACE_OVERLAY" && -d "$DIR/namespace-overlays/$NAMESPACE_OVERLAY" ]]; then
    echo "Namespace overlay $NAMESPACE_OVERLAY is being used for namespace $NAMESPACE"
    helm install nginx-ingress ${DIR}/charts/ingress-nginx \
        --namespace=$NAMESPACE \
        --values "$DIR/namespace-overlays/$NAMESPACE_OVERLAY/values.yaml" \
        --set controller.image.chroot="${IS_CHROOT}" \
        --set controller.image.repository="${REGISTRY}/ingress-controller" \
        --set controller.image.tag="${TAG}" \
        ${HELM_ARGS} \
        --set controller.wallarm.enabled="${WALLARM_ENABLED}" \
        --set controller.wallarm.token="${WALLARM_API_TOKEN}" \
        --set controller.wallarm.apiHost="${WALLARM_API_HOST}" \
        --set controller.wallarm.fallback="off"
else
    cat << EOF | helm install nginx-ingress ${DIR}/charts/ingress-nginx --namespace=$NAMESPACE ${HELM_ARGS} --values -
# TODO: remove the need to use fullnameOverride
fullnameOverride: nginx-ingress
controller:
  enableAnnotationValidations: ${ENABLE_VALIDATIONS}
  wallarm:
    enabled: ${WALLARM_ENABLED}
    token: ${WALLARM_API_TOKEN}
    apiHost: ${WALLARM_API_HOST}
    fallback: "off"
  image:
    repository: ${REGISTRY}/ingress-controller
    chroot: ${IS_CHROOT}
    tag: ${TAG}
    digest:
    digestChroot:
  scope:
    enabled: true
  config:
    worker-processes: "1"
  readinessProbe:
    initialDelaySeconds: 3
    periodSeconds: 1
  livenessProbe:
    initialDelaySeconds: 3
    periodSeconds: 1
  service:
    type: NodePort
  electionID: ingress-controller-leader
  ingressClassResource:
    # We will create and remove each IC/ClusterRole/ClusterRoleBinding per test so there's no conflict
    enabled: false
  extraArgs:
    tcp-services-configmap: $NAMESPACE/tcp-services
    # e2e tests do not require information about ingress status
    update-status: "false"
  terminationGracePeriodSeconds: 1
  admissionWebhooks:
    enabled: false
  metrics:
    enabled: true

  # ulimit -c unlimited
  # mkdir -p /tmp/coredump
  # chmod a+rwx /tmp/coredump
  # echo "/tmp/coredump/core.%e.%p.%h.%t" > /proc/sys/kernel/core_pattern
  extraVolumeMounts:
    - name: coredump
      mountPath: /tmp/coredump

  extraVolumes:
    - name: coredump
      hostPath:
        path: /tmp/coredump

${OTEL_MODULE}

rbac:
  create: true
  scope: true

EOF

fi
