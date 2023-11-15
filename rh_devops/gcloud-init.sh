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

# Check correct version of GCloud SDK is installed
GCLOUD_MIN_VERSION=455
gcloud_version=$(gcloud --version |grep 'Google Cloud SDK' |awk '{print $NF}' |awk -F. '{print $1}')
if [ ${gcloud_version} -lt ${GCLOUD_MIN_VERSION} ]; then
    echo "GCloud SDK version ${GCLOUD_MIN_VERSION} or greater is required!!!"
    echo "See instruction at https://cloud.google.com/sdk/docs/install-sdk"
    exit 1
fi

# Check if gcloud authentication is complete
is_authed=$(gcloud auth list 2> /dev/null |grep '^\*' |grep -v gserviceaccount.com || true)
if [ -z "${is_authed}" ]; then
    gcloud auth login --no-launch-browser
fi

# Enable GCloud API Endpoints
gcloud services --project ${GCLOUD_PROJECT} enable iam.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable iam
gcloud services --project ${GCLOUD_PROJECT} enable container.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable container
gcloud services --project ${GCLOUD_PROJECT} enable compute.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable compute
gcloud services --project ${GCLOUD_PROJECT} enable cloudbuild.googleapis.com
gcloud services --project ${GCLOUD_PROJECT} enable cloudresourcemanager.googleapis.com

# Create service account for Terraform
sa_path="projects/${GCLOUD_PROJECT}/serviceAccounts/terraform@${GCLOUD_PROJECT}.iam.gserviceaccount.com"
sa_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts list |jq -r '.[] |select(.name=="'${sa_path}'") |.uniqueId')
if [ -z "${sa_id}" ]; then
    sa_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts create terraform |jq -r '.uniqueId')
fi

# Create key for service account
sa_key_file=".modules/${ENV}/secret/terraform_key.json"
sa_key_id=$(jq -r '.private_key_id' ${sa_key_file} || true)
if [ -n "${sa_key_id}" ]; then
    sa_key_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts keys list --iam-account ${sa_id} |jq -r '.[] |select(.name=="'${sa_path}/keys/${sa_key_id}'") |.name' |awk -F/ '{print $NF}' || true)
fi
if [ -z "${sa_key_id}" ]; then
    gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts keys create ${sa_key_file} --iam-account ${sa_id}
fi
