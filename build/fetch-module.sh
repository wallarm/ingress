#!/bin/bash

set -e

TARGETS_MODULES="rootfs/modules"
AIO_VERSION=$(cat AIO_BASE)
[ $ARCH == "amd64" ] && AIO_ARCH=x86_64 || AIO_ARCH=aarch64
AIO_URL="https://storage.googleapis.com/meganode_storage/${AIO_VERSION%.*}/wallarm-${AIO_VERSION}.${AIO_ARCH}-musl.tar.gz"

echo "Downloading AIO archive (${ARCH}/${AIO_ARCH})"
mkdir -p "${TARGETS_MODULES}/${ARCH}"
curl -L -C - -o "wallarm-${ARCH}.tar.gz" "$AIO_URL"
echo "Extracting ngx_http_wallarm_module (${ARCH}/${AIO_ARCH})"
tar xvf wallarm-${ARCH}.tar.gz -C "$TARGETS_MODULES/$ARCH" --strip-components=4 /opt/wallarm/modules/ingress-1216/ngx_http_wallarm_module.so

NGINX_VERSION=$(cat NGINX_BASE)
docker image rm $NGINX_VERSION || true
NGX_VER=$(docker run --rm --platform $ARCH $NGINX_VERSION sh -c "nginx -v 2>&1 | grep -o '[0-9.]*$'")
NGX_SIG=$(docker run --rm --platform $ARCH $NGINX_VERSION grep -E -o '.,.,.,[01]{33}' /sbin/nginx)
F_VER=`grep -ao -P '(nginx|openresty)\/\K\d+(\.\d+){2,}(?=( \(.*\)$|$))' "$TARGETS_MODULES/$ARCH/ngx_http_wallarm_module.so"`
F_SIG=`egrep -ao '.,.,.,[01]{33}' "$TARGETS_MODULES/$ARCH/ngx_http_wallarm_module.so"`
if [ "${NGX_VER}" == "${F_VER}" ] && [ "${NGX_SIG}" == "${F_SIG}" ]; then
  echo "OK! Version and signature of nginx module match expectations from version and signature of nginx binary found in the base image"
else
  echo "Failure! Version and signature of module: $F_VER / $F_SIG . Found in nginx binary: $NGX_VER / $NGX_SIG"
  exit 1
fi
