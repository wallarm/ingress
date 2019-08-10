FROM quay.io/kubernetes-ingress-controller/e2e:v02262020-a830e931d AS BASE

FROM alpine:3.11

RUN apk add -U --no-cache \
    ca-certificates \
    bash \
    curl \
    tzdata \
    libc6-compat \
    openssl

RUN curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash \
  && helm repo add stable https://kubernetes-charts.storage.googleapis.com \
  && helm repo update

RUN curl -Lo /usr/local/bin/kubectl \
    https://storage.googleapis.com/kubernetes-release/release/v1.17.0/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl

COPY --from=BASE /go/bin/ginkgo /usr/local/bin/
COPY --from=BASE /usr/local/bin/kubectl /usr/local/bin/

COPY e2e.sh             /e2e.sh
COPY namespace-overlays /namespace-overlays

COPY manifests          /manifests
COPY wait-for-nginx.sh  /
COPY e2e.test           /
COPY ca.pem             /
COPY charts /charts

CMD [ "/e2e.sh" ]
