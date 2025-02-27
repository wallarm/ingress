#!/bin/sh
set -eu

apk update && apk add --no-cache grep
GREP_CMD="grep"

determine_nginx_version() {
    ${GREP_CMD} -aoP '(nginx|openresty)\/\K\d+(\.\d+){2,}(?=( \(.*\)$|$))' "${1}" | uniq
}

determine_nginx_signature34() {
    ${GREP_CMD} -aoP '[0-9],[0-9],[0-9],[01]{34}' "${1}" | uniq
}

pick_module() {
    # Environment
    CUSTOM_NGX_BUILD="${CUSTOM_NGX_BUILD:-0}"

    NGINX="${1:-}"
    if [ "${NGINX}" = "" ] ; then
        NGINX="$(which nginx)"
        echo "[i] Auto-detected nginx: ${NGINX}" >&2
    fi

    CWD="$(realpath "${0}")"
    CWD="${CWD%/*}"
    NGINX_TEST_CONF="${CWD}/nginx-test.conf"

    cd ${CWD}

    echo "[i] Running from PWD='${PWD}' CWD='${CWD}', modules available:" >&2
    echo "$(ls modules 2> /dev/null)" >&2

    NGX_VER="$(determine_nginx_version "${NGINX}")"
    NGX_SIG="$(determine_nginx_signature34 "${NGINX}")"

    for f in modules/*/ngx_http_wallarm_module.so ; do
        if [ "${CUSTOM_NGX_BUILD}" = "1" ] ; then
            # Use only non-patched modules for custom builds
            if echo "${f}" | grep -E -q '_p[0-9a-f]{9}/ngx_http_wallarm_module\.so$' ; then
                echo "[i] Skipping patched module ${f}" >&2
                continue
            fi
        fi

        F_VER="$(determine_nginx_version "${f}")"
        if [ "${NGX_VER}" != "${F_VER}" ] ; then
            continue
        fi
        F_SIG="$(determine_nginx_signature34 "${f}")"
        if [ "${NGX_SIG}" != "${F_SIG}" ] ; then
            continue
        fi

        if ! WALLARM_COMPATIBLE_EXECUTABLE_STRICT_CHECK=true "${NGINX}" -p "${CWD}" -c "${NGINX_TEST_CONF}" -g "error_log /dev/stderr debug; load_module ${PWD}/${f};" -t ; then
            if [ "${CUSTOM_NGX_BUILD}" != "1" ] ; then
                # For public (non-custom) builds, require hash match
                continue
            fi

            # If the failure does not belong to the hash check, then the module does not match for a reason
            if ! WALLARM_COMPATIBLE_EXECUTABLE_STRICT_CHECK=false "${NGINX}" -p "${CWD}" -c "${NGINX_TEST_CONF}" -g "error_log /dev/stderr debug; load_module ${PWD}/${f};" -t ; then
                continue
            fi

            # Assume match
        fi

        echo "${f}"
        return
    done
}

pick_module "${@}"