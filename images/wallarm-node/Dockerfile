# Copyright 2018 Wallarm Inc. All rights reserved.
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


FROM BASEIMAGE

RUN apt-get -qq update && apt-get -qq -y install curl gnupg2 \
    && curl -fsSL https://repo.wallarm.com/wallarm.gpg | apt-key add - \
    && echo 'deb http://repo.wallarm.com/debian/wallarm-node buster/3.0/' \
        > /etc/apt/sources.list.d/wallarm.list \
    && apt-get -qq update \
    && apt-get -qq --no-install-recommends install \
        nginx-module-wallarm-k8s-ingress \
        wallarm-node \
    && apt-get -y remove curl \
    && apt-get -y dist-upgrade \
    && chown www-data:www-data /var/lib/wallarm-tarantool \
    && chown www-data:www-data /var/lib/collectd \
    && find /var/lib/apt -type f -delete
