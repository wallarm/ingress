#!/bin/bash

set -e

TARGETS_MODULES="rootfs/modules"
TARGETS_PAGES="rootfs/usr"
TMP_TARGET_DIR="/tmp/opt/wallarm"

AIO_VERSION=$(cat AIO_BASE)
[ "${ARCH}" == "amd64" ] && AIO_ARCH=x86_64 || AIO_ARCH=aarch64
AIO_FILE="wallarm-${AIO_VERSION}.${AIO_ARCH}-musl.sh"
AIO_URL="https://storage.googleapis.com/meganode_storage/${AIO_VERSION%.*}/${AIO_FILE}"

# ingress controller is currently based on nginx 1.25.5
NGINX_VER=1255

# grep on Mac OS comes from FreeBSD not GNU, and it does not have option -P. Need to install ggrep by `brew install grep`
GREP_CMD=$(which grep)

if [[ "$OSTYPE" == darwin* ]]; then
  if ! command -v ggrep &> /dev/null
  then
    echo "ggrep could not be found. Run \"brew install grep\""
    exit 1
  fi
  GREP_CMD=$(which ggrep)
fi


if ! test -f "${AIO_FILE}"; then
  echo "Downloading AIO archive (${ARCH}/${AIO_ARCH})"
  curl -L -C - -o "${AIO_FILE}" "${AIO_URL}"
  chmod +x "${AIO_FILE}"
fi

echo "Extracting AIO to (${TMP_TARGET_DIR})"
sh -c "./${AIO_FILE} --noexec --target ${TMP_TARGET_DIR}"

echo "Overriding pick-module.sh with custom version from repository"
cp build/pick-module.sh "${TMP_TARGET_DIR}/pick-module.sh"
chmod +x "${TMP_TARGET_DIR}/pick-module.sh"

# New: Dynamically pick the proper module using the pick-module.sh script inside a Docker container.
NGINX_BASE=$(cat NGINX_BASE)
if [ "${ARCH}" = "arm64" ]; then
    # Remove digest so Docker pulls the correct multi-arch image.
    NGINX_BASE=$(echo "$NGINX_BASE" | sed 's/@.*//')
fi

echo "Running dynamic module selection via pick-module.sh in container"
# Filter output so only valid module paths (starting with "modules/") are captured.
MODULE_REL_PATH=$(docker run --rm -v "${TMP_TARGET_DIR}:${TMP_TARGET_DIR}" --platform "linux/${ARCH}" "${NGINX_BASE}" sh -c "sh ${TMP_TARGET_DIR}/pick-module.sh" | grep '^modules/' | tail -n 1)
if [ -z "${MODULE_REL_PATH}" ]; then
  echo "Error: pick-module.sh did not return a module path." >&2
  exit 1
fi
MODULE_FULL_PATH="${TMP_TARGET_DIR}/${MODULE_REL_PATH}"
echo "Dynamic module selected: ${MODULE_FULL_PATH}"

mkdir -p "${TARGETS_MODULES}/${ARCH}"
mkdir -p "${TARGETS_MODULES}/${ARCH}/libwallarm"
echo "Copying dynamic nginx module (${ARCH})"
cp "${MODULE_FULL_PATH}" "${TARGETS_MODULES}/${ARCH}/ngx_http_wallarm_module.so"
echo "Copying libwallarm (${ARCH})"
ls -la ${TMP_TARGET_DIR}/modules/
cp -a ${TMP_TARGET_DIR}/modules/libwallarm.so* "${TARGETS_MODULES}/${ARCH}/libwallarm"

mkdir -p "${TARGETS_PAGES}"
echo "Copy wallarm_blocked.html page"
cp "${TMP_TARGET_DIR}/usr/share/nginx/html/wallarm_blocked.html" "${TARGETS_PAGES}/wallarm_blocked.html"

echo "Clean ${TMP_TARGET_DIR}"
rm -rf "${TMP_TARGET_DIR}"

# Remove the image to allow pulling different architectures on the same runner.
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
