#!/bin/bash

set -e
set -o pipefail

if [[ ! $AIO_VERSION =~ "rc" ]]; then
    IFS=- read -r VERSION SUFFIX <<< "$AIO_VERSION"
    IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"

    helm repo add wallarm https://charts.wallarm.com && helm repo update wallarm || exit 1
    LATEST=$(helm search repo wallarm/wallarm-ingress --version ${MAJOR}.${MINOR} -o json | jq -r '.[].version')

    if [ -z "$LATEST" ]; then
        LATEST_PATCH=-1
    else
        LATEST_PATCH=$(cut -d'.' -f3 <<< $LATEST)
    fi
    echo "Detected latest release as ${LATEST:-none}"

    if [ $PATCH -gt $LATEST_PATCH ]; then
        echo "Chart with version $AIO_VERSION doesn't exist yet, re-using AIO_VERSION for the new chart version"
        TAG=$AIO_VERSION
    else
        echo "Chart with version $AIO_VERSION (or later) exists already, will increment chart patch version..."
        TAG=$(echo "${MAJOR}.${MINOR}.$((${LATEST_PATCH} + 1))")
        [ ! -z $SUFFIX ] && TAG="${TAG}-${SUFFIX}"
    fi
else
    echo "AIO_VERSION is RC, if IC image with the same tag exists already it will be overwritten"
    TAG=$AIO_VERSION
fi

# Generally, we assume that versions are in sync.
# But cases when ingress version (chart version) is larger than that of AIO, and/ or of controller image, may occur, due to ingress-specific patching
# In these cases, we use the chart version as a reference for "latest", and publish new controller image and chart using that version and adding +1
echo "Chosen TAG $TAG"
echo "TAG=$TAG" > version.env
