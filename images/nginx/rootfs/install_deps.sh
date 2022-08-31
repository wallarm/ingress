#!/bin/bash

set -ex

PKGS_BRANCH=stable/4.2
export CFLAGS="-fPIC -fno-omit-frame-pointer -O2 -ggdb3"
export CXXFLAGS="$CFLAGS"

apk add openssh-client-default sudo \
 tcl `#sqlite3` \
 cunit-dev `#wacl` \
 re2c bsd-compat-headers `#libdetect` \
 texinfo `#libconfig`

ARRAY=(
 "https://github.com/maxmind/libmaxminddb.git;1.6.0"
 "https://github.com/sqlite/sqlite.git;version-3.39.2"
 "git@gl.wallarm.com:wallarm-node/libs/libwacl.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libwallarmmisc.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libdetection.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libbrotli.git;$PKGS_BRANCH"
 "https://github.com/hyperrealm/libconfig.git;v1.7.3"
 "git@gl.wallarm.com:wallarm-node/libs/libwpire.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libcpire.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libparserutils.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libhubbub.git;$PKGS_BRANCH"
 "https://github.com/GNOME/libxml2.git;v2.9.14"
 "git@gl.wallarm.com:wallarm-node/libs/libwlog.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libtws.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libwyajl.git;$PKGS_BRANCH"
 "git@gl.wallarm.com:wallarm-node/libs/libproton.git;$PKGS_BRANCH"
 "https://github.com/yaml/libyaml.git;0.2.5"
 "git@gl.wallarm.com:wallarm-node/wallarm-nginx.git;$PKGS_BRANCH"
)

mkdir -p ~/.ssh || true
cat ~/.ssh/known_hosts | grep gl.wallarm.com || ssh-keyscan gl.wallarm.com >> ~/.ssh/known_hosts
ssh-add -l

rm -rf /tmp/pkgs
mkdir -p /tmp/pkgs
cd /tmp/pkgs

for str in "${ARRAY[@]}" ; do
    REPO="${str%%;*}"
    TAG="${str##*;}"
    PKG=${REPO##*/}
    PKG=${PKG%%.*}

    git clone --depth 1 --branch "${TAG}" "${REPO}"

    cd "${PKG}"
    bash -ex /recipes/"${PKG}".sh
    cd -
done
