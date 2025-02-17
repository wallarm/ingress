#!/usr/bin/env bash

set -o errexit
set -o pipefail


IMAGE_NAME=${REGISTRY}/${IMAGE}:${TAG}
echo "Will be signing: ${IMAGE_NAME}..."
docker pull -q ${IMAGE_NAME}

IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE_NAME)
IMAGE_URI=$(echo $IMAGE_DIGEST | sed -e 's/\@sha256:/:sha256-/')


SBOM_SPDX="${CI_PROJECT_DIR}/sbom_${TAG}_spdx.json"
syft -o spdx-json $IMAGE_NAME > $SBOM_SPDX

cosign attach sbom --sbom $SBOM_SPDX $IMAGE_DIGEST
cosign sign --yes --key env://COSIGN_PRIVATE "$IMAGE_URI.sbom"
cosign sign --recursive --yes --key env://COSIGN_PRIVATE $IMAGE_DIGEST
