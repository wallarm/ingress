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

RUN echo "mQINBFL1Xl4BEADEFCVumPx2W4hQJG+4RRS0Zjw503a0YKH8tKp3OEWIMKiWwWiaTcqxZghCZlm+"\
"MytwVmhX4pfEnkGyWdQTZOYosukTYqqYWnVEtqxTaep1k9JnUJ4rHsBUXIbnkL01rjLAkCxTTCMP"\
"zfQJNsqESnjllX6Ov/DtEm7EvilWdkkVK9TPF/tD0YwmIKz+nIR6Vylwy71f4hI6O2+91D5UJg/F"\
"ardAner3rbIzYsRLgbAwx+5V8T9HSVWcjwAknpXDll6mvwionS5Aq+0hSuSjjABcZ2D7EW955ecb"\
"2Ql4fOEJPdmUQ//pHMHFgF85j4zwK5gfx9qLeTcmPxi1o14qmaKiZgfh7PxedScZP0VXN9B7Z9NF"\
"po2ZQHqcBAK23msd+wnT4QMkC0CMLpw6AM0KmyNDVrVlTCytucg0zLBTBojEwSW6EzMSBVKip22q"\
"T4RelL3ykoHIHOoXbHPqSgdy+ba0A+gsfXmYHSOS/GjtNesgHTkUvylniZXyCGCy3Rqt+QzBWB2w"\
"Xr2zQ13GJpnLprvtrVLx+GX0oHk6hF21Vm4iCFiw3eE8dI1y8wR2kDFjdwyduQPLXXPjt7aEdzCL"\
"oCaFRYju8k4jSGEaWa79jBvDer1fKhtHUmMz7HLmRRfKCSuJqMRJCU9spknt7g4e33OkKQprU+4Y"\
"5V7gtpMq1O/ECQARAQABtEBXYWxsYXJtIERlYmlhbiBHTlUvTGludXggcGFja2FnZXMgcmVwb3Np"\
"dG9yeSA8YWRtaW5Ad2FsbGFybS5jb20+iQI+BBMBAgAoBQJS9V5eAhsDBQkJZgGABgsJCAcDAgYV"\
"CAIJCgsEFgIDAQIeAQIXgAAKCRAJY9VBcrhl/UWID/4pcIjqrzT3qM6SF9owaPmvB311hzghrzc7"\
"z3IEWn4gKZDF1Z9YMgWovTKZ+/0j3xzk66jnmcA2xnYOpKXLmrfiFC4QmQKbSoq4bKAiVx5q2nuU"\
"osxOUFODIvs5ORR4R75mW2I5f8aes/3+7vIxDEt9aYMEqqV7bc6/87lCqGMNQ6przIgRo2sXpt0d"\
"rtK3TagjNwlDqihd7lx3/7VRt3G0Pi17rlfLGp4QjCeGoNmBRpLhM//USRR5J2sfFDFU09Zz/SV4"\
"7/QMI2isUaehHoAm3JHzC2RUDt8gpzjTop+ill/8Xbwr6Lh3WGsWRCsTlKAl2V9I5EiX+Hr8bTKT"\
"QG0pP1gBwnWb6zhThpBH+a303orsmu6GLOXjmTNjCNjlFdh8qW4+FgeZQuvC3m5oQC/7JBYrwuZF"\
"HTfsgoZtSKAoyy4IFZUCK3kbwuZLeKPW8GSrfXmo6Z+y5DFYQZcWTGpW+ogWrHJME8h0TmaID3fo"\
"3CVPX/MAhZfmeQy8Hb/NAw3/V7Dx5PWBguAbrNswjnf5w78RChPiCjRvA7wqK6eRCuw9Lg+C2Crq"\
"a5M67AEGd9tOwE315L27lM9gViH+Pv4L0fJOtUsRyTftSx0nOLJF89XadRjmFVWZ5/1X8jaQ0vmN"\
"LTrSJw61vH6hS/oaAZ/zmKdciNja23uQ5HK+nhIquQ==" \
        | base64 -d > /etc/apt/trusted.gpg.d/wallarm.gpg \
    && echo 'deb http://repo.wallarm.com/debian/wallarm-node stretch/' \
        > /etc/apt/sources.list.d/wallarm.list \
    && apt-get -qq update \
    && apt-get -qq --no-install-recommends install \
        nginx-module-wallarm-k8s-ingress \
        wallarm-node \
    && chown www-data:www-data /var/lib/nginx /var/lib/wallarm-tarantool \
    && find /var/lib/apt -type f -delete

