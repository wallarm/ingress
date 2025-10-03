#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME=docker.io/wallarm/${IMAGE}:${TAG}
echo "Will be signing: ${IMAGE_NAME}..."
docker pull -q ${IMAGE_NAME}

IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE_NAME)
IMAGE_URI=$(echo $IMAGE_DIGEST | sed -e 's/\@sha256:/:sha256-/')

export SBOM_SPDX="${CI_PROJECT_DIR}/sbom_${IMAGE}_${TAG}_spdx.json"
export PROVENANCE_PREDICATE="${CI_PROJECT_DIR}/provenance_${IMAGE}_${TAG}.json"
syft -o spdx-json ${IMAGE_NAME} > ${SBOM_SPDX}

export IMAGE_SHA="${IMAGE_DIGEST##*:}"
export BUILD_FINISHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
apk add --no-cache python3 >/dev/null 2>&1 || apk add --no-cache python3
python3 .gitlab/generate_provenance.py

cosign attest --yes --key env://COSIGN_PRIVATE --type spdxjson --predicate ${SBOM_SPDX} ${IMAGE_DIGEST}
cosign attest --yes --key env://COSIGN_PRIVATE --type slsaprovenance1 --predicate ${PROVENANCE_PREDICATE} ${IMAGE_DIGEST}
cosign sign --recursive --yes --key env://COSIGN_PRIVATE ${IMAGE_DIGEST}
