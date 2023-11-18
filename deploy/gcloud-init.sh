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
gcloud components install gke-gcloud-auth-plugin --quiet

# Check if gcloud authentication is complete
is_authed=$(gcloud auth list 2> /dev/null |grep '^\*' |grep terraform@${GCLOUD_PROJECT}.iam.gserviceaccount.com || true)
if [ -z "${is_authed}" ]; then
    is_authed=$(gcloud auth list 2> /dev/null |grep '^\*' |grep -v gserviceaccount.com || true)
    if [ -z "${is_authed}" ]; then
        gcloud auth login --no-launch-browser
    fi
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

${dir}/gcloud-sa-create.sh
${dir}/gcloud-gke-create.sh
${dir}/k8s-certman-create.sh
