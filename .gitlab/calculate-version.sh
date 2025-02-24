#!/bin/bash

if [[ ! $AIO_VERSION =~ "rc" ]]; then
    if docker pull -q wallarm/ingress-controller:${AIO_VERSION} ; then
        echo "Image AIO_VERSION $AIO_VERSION exists already, will increment IC patch version..."
        IFS=- read -r VERSION SUFFIX <<< "$AIO_VERSION"
        IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"

        helm repo add wallarm https://charts.wallarm.com && helm repo update wallarm
        LATEST=$(helm search repo wallarm/wallarm-ingress --version ^${MAJOR}.${MINOR} -o json | jq -r '.[].version')
        LATEST_PATCH=$(cut -d'.' -f3 <<< $LATEST)
        echo "Detected latest release as $LATEST"

        TAG=$(echo "${MAJOR}.${MINOR}.$((${LATEST_PATCH} + 1))")
        [ ! -z $SUFFIX ] && TAG="${TAG}-${SUFFIX}"
    else
        echo "Image with tag $AIO_VERSION doesn't exist yet, re-using AIO_VERSION for the new image tag"
        TAG=$AIO_VERSION
    fi
else
    echo "AIO_VERSION is RC, if IC image with the same tag exists already it will be overwritten"
    TAG=$AIO_VERSION
fi

echo "TAG=$TAG" > version.env
