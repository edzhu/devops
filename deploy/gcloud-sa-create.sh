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

# Create service account for Terraform
sa_path="projects/${GCLOUD_PROJECT}/serviceAccounts/terraform@${GCLOUD_PROJECT}.iam.gserviceaccount.com"
sa_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts list |jq -r '.[] |select(.name=="'${sa_path}'") |.uniqueId')
if [ -z "${sa_id}" ]; then
    sa_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts create terraform |jq -r '.uniqueId')
fi

# Create and download key for service account
sa_key_file="${dir}/../.modules/${ENV}/secret/terraform_key.json"
sa_key_id=$(jq -r '.private_key_id' ${sa_key_file} || true)
if [ -n "${sa_key_id}" ]; then
    sa_key_id=$(gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts keys list --iam-account ${sa_id} |jq -r '.[] |select(.name=="'${sa_path}/keys/${sa_key_id}'") |.name' |awk -F/ '{print $NF}' || true)
fi
if [ -z "${sa_key_id}" ]; then
    gcloud --format=json iam --project ${GCLOUD_PROJECT} service-accounts keys create ${sa_key_file} --iam-account ${sa_id}
fi

# Add cluster management permissions to service account
sa_name="serviceAccount:terraform@${GCLOUD_PROJECT}.iam.gserviceaccount.com"
is_authorized=$(gcloud --format=json projects get-iam-policy ${GCLOUD_PROJECT} |jq -r '.bindings.[] |select(.role=="roles/container.serviceAgent") |.members.[]' |grep ${sa_name} || true)
if [ -z "${is_authorized}" ]; then
    is_authorized=$(gcloud projects add-iam-policy-binding ${GCLOUD_PROJECT} --member ${sa_name} --role roles/container.serviceAgent |jq -r '.bindings.[] |select(.role=="roles/container.serviceAgent") |.members.[]' |grep ${sa_name})
    if [ -z "${is_authorized}" ]; then
        echo "Failed to bind container.serviceAgent role to ${sa_name}"
        exit 1
    fi
fi

# Activate the service account
gcloud auth activate-service-account --key-file=${sa_key_file}
