REGISTRY ?= wallarm
TAG ?= dev
IMAGE=$(REGISTRY)/wallarm-api-proxy

.PHONY: all container

all: container

container:
	cp ../../test/e2e-image/ca.pem .
	docker build -t $(IMAGE):$(TAG) .