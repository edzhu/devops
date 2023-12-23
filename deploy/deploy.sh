#!/bin/bash -xe
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

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

SA_NAME=terraform

${dir}/install-gcloud.sh ${SA_NAME}

# Enable GCloud API Endpoints
gcloud services --project ${GCLOUD_PROJECT} enable iam.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable iam
gcloud services --project ${GCLOUD_PROJECT} enable container.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable container
gcloud services --project ${GCLOUD_PROJECT} enable compute.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable compute
gcloud services --project ${GCLOUD_PROJECT} enable cloudbuild.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable cloudresourcemanager.googleapis.com

${dir}/gcloud-sa-create.sh
${dir}/gcloud-gke-create.sh

# Create Kubernetes namespace
has_namespace=$(kubectl get namespace ${K8S_NAMESPACE} 2> /dev/null || true)
if [ -z "${has_namespace}" ]; then
    kubectl create namespace ${K8S_NAMESPACE}
fi

${dir}/k8s-nginx-create.sh
${dir}/k8s-certman-create.sh
