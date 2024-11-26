#!/bin/bash

set -e

TARGETS_MODULES="rootfs/modules"
TARGETS_PAGES="rootfs/usr"

AIO_VERSION=$(cat AIO_BASE)
[ "${ARCH}" == "amd64" ] && AIO_ARCH=x86_64 || AIO_ARCH=aarch64
AIO_FILE="wallarm-${AIO_VERSION}.${AIO_ARCH}-musl.tar.gz"
AIO_URL="https://storage.googleapis.com/meganode_storage/${AIO_VERSION%.*}/${AIO_FILE}"

# ingress controller is currently based on nginx 1.25.5
NGINX_VER=1255

# grep on Mac OS comes from FreeBSD not GNU, and it does not have option -P. Need to install ggrep by `brew install grep`
GREP_CMD=$(which grep)
STRIP_N=0
if [[ "$OSTYPE" == darwin* ]]; then
  if ! command -v ggrep &> /dev/null
  then
    echo "ggrep could not be found. Run \"brew install grep\""
    exit 1
  fi
  GREP_CMD=$(which ggrep)
  STRIP_N=1
fi


if ! test -f "${AIO_FILE}"; then
  echo "Downloading AIO archive (${ARCH}/${AIO_ARCH})"
  curl -L -C - -o "${AIO_FILE}" "${AIO_URL}"
fi

mkdir -p "${TARGETS_MODULES}/${ARCH}"
echo "Extracting ngx_http_wallarm_module (${ARCH}/${AIO_ARCH})"
tar -xvf "${AIO_FILE}" -C "${TARGETS_MODULES}/${ARCH}" --strip-components="$((4 + ${STRIP_N}))" "/opt/wallarm/modules/ingress-${NGINX_VER}/ngx_http_wallarm_module.so"

mkdir -p "${TARGETS_PAGES}"
echo "Extracting wallarm_blocked.html page"
tar -xvf "${AIO_FILE}" -C "${TARGETS_PAGES}" --strip-components="$((6 + ${STRIP_N}))" "/opt/wallarm/usr/share/nginx/html/wallarm_blocked.html"

# image rm is needed to be able to pull two samely tagged images for different platforms (as we execute on the same runner)
NGINX_BASE=$(cat NGINX_BASE)
docker image rm "${NGINX_BASE}" || true

# making sure signatures of nginx binary and our module match to avoid shipping broken installs, logic from AiO
NGX_VER=$(docker run --rm --platform "linux/${ARCH}" "${NGINX_BASE}" sh -c "nginx -v 2>&1 | grep -o '[0-9.]*$'")
NGX_SIG=$(docker run --rm --platform "linux/${ARCH}" "${NGINX_BASE}" grep -E -o '.,.,.,[01]{33}' /sbin/nginx)
MOD_VER=$(${GREP_CMD} -ao -P '(nginx|openresty)\/\K\d+(\.\d+){2,}(?=( \(.*\)$|$))' "${TARGETS_MODULES}/${ARCH}/ngx_http_wallarm_module.so")
MOD_SIG=$(grep -E -ao '.,.,.,[01]{33}' "${TARGETS_MODULES}/${ARCH}/ngx_http_wallarm_module.so")
if [ "${NGX_VER}" == "${MOD_VER}" ] && [ "${NGX_SIG}" == "${MOD_SIG}" ]; then
  echo "OK! Version and signature of nginx module match expectations from version and signature of nginx binary found in the base image"
else
  echo "Failure! Version and signature of module: ${MOD_VER} / ${MOD_SIG}. Found in nginx binary: ${NGX_VER} / ${NGX_SIG}"
  exit 1
fi
