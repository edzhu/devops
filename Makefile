#
# REFUND HUNTER CONFIDENTIAL
# __________________________
#
#  [2017] - [2023] Refund Hunter
#  All Rights Reserved.
#
# NOTICE: All information contained herein is, and remains the property of Refund Hunter and its
# suppliers, if any.  The intellectual and technical concepts contained herein are proprietary to
# Refund Hunter and its suppliers and may be covered by U.S. and Foreign Patents, patents in
# process, and are protected by trade secret or copyright law. Dissemination of this information or
# reproduction of this material is strictly forbidden unless prior written permission is obtained
# from Refund Hunter.
#
pull:

export DOMAIN_PREFIX ?= rh-
export ENV ?= $(shell git rev-parse --abbrev-ref HEAD | awk -F- '{print $$1}')
export GIT_DOMAIN ?= github.com
export GIT_USER ?= ${USER}

ifeq ($(ENV), ops)
	export GCLOUD_LOCATION ?= us-central1  # regional cluster

else ifeq ($(ENV), prd)
	export GCLOUD_LOCATION ?= us-central1-c  # zonal cluster

else ifeq ($(ENV), tst)
	export GCLOUD_LOCATION ?= us-central1-f  # zonal cluster

else
	export ENV = dev
	export GCLOUD_LOCATION ?= us-central1-b  # zonal cluster
endif

export GIT_SUFFIX ?= $(shell git rev-parse --abbrev-ref HEAD | awk -F- '{print $$2}' | sed 's|\([0-9]\)|-\1|')
export GIT_REPO ?= $(shell git remote -v |head -n 1 |awk -F${GIT_DOMAIN}. '{print $$2}' |awk '{print $$1}' |awk -F. '{print $$1}' |tr '/' '_')
export GCLOUD_PROJECT = $(DOMAIN_PREFIX)$(ENV)

export IMAGE_NAME := $(shell echo ${GIT_REPO}${GIT_SUFFIX} |sed 's|_|-|g')
export IMAGE_REPO = gcr.io/$(GCLOUD_PROJECT)/$(IMAGE_NAME)
export IMAGE_TAG ?= $(shell date +%s)

export DOCKER_IMAGE := $(IMAGE_REPO):$(IMAGE_TAG)
export K8S_NAMESPACE := $(IMAGE_NAME)
export K8S_CLUSTER := $(DOMAIN_PREFIX)$(ENV)
export K8S_CONTEXT = $(shell echo gke_${GCLOUD_PROJECT}_${GCLOUD_LOCATION}_${K8S_CLUSTER} |sed 's|"||g')

.PHONY: pull
pull:
	@git pull
	@git submodule update --init --recursive

.PHONY: clean
clean:
	@rm -rf build dist
	@find . -name '__pycache__' -type d |xargs rm -rf
	@find . -name '*.egg-info' -type f -delete
	@find . -name '*~' -type f -delete

.PHONY: gcloud-auth
gcloud-auth:
	@gcloud container clusters get-credentials $(K8S_CLUSTER) \
		--location $(GCLOUD_LOCATION) --project $(GCLOUD_PROJECT)

.PHONY: kub
kub: gcloud-auth
	@kubectl create namespace $(K8S_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl config set-context $(shell kubectl config current-context) --namespace=$(K8S_NAMESPACE)

.PHONY: deploy
deploy:
	@deploy/deploy.sh

.PHONY: shutdown
shutdown:
	@deploy/k8s-gitlab-destroy.sh
	@deploy/k8s-certman-destroy.sh
	@deploy/k8s-nginx-destroy.sh

.PHONY: deploy-gitlab
deploy-gitlab:
	@deploy/k8s-gitlab-create.sh

.PHONY: shutdown-gitlab
shutdown-gitlab:
	@deploy/k8s-gitlab-destroy.sh
