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

location_components=$(echo ${GCLOUD_LOCATION} |awk -F- '{print NF}')
if [ ${location_components} -eq 3 ]; then
    autopilot=false
elif [ ${location_components} -eq 2 ]; then
    autopilot=true
else
    echo Unexpected Gcloud location format: ${GCLOUD_LOCATION}
    exit 1
fi

is_autopilot=$(gcloud --format=json container --project ${GCLOUD_PROJECT} clusters list |jq '.[] |select(.name=="'${K8S_CLUSTER}'") |.autopilot.enabled')
if [ -z "${is_autopilot}" ]; then
    # TODO: handling non-autopilot cluster creation
    is_autopilot=$(gcloud --format=json container --project ${GCLOUD_PROJECT} clusters create-auto ${K8S_CLUSTER} --location=${GCLOUD_LOCATION} |jq '.[] |select(.name=="'${K8S_CLUSTER}'") |.autopilot.enabled')

fi

if [ ${is_autopilot} != ${autopilot} ]; then
    echo "Unable to create cluster ${K8S_CLUSTER} in GCloud project ${GCLOUD_PROJECT}"
    exit 1
fi

# Set container authentication to default namespace
gcloud container clusters get-credentials ${K8S_CLUSTER} --location=${GCLOUD_LOCATION} --project=${GCLOUD_PROJECT}
kubectl config set-context $(kubectl config current-context) --namespace=default

# Add GKD specific storage classes
kubectl apply -f ${dir}/k8s-gke-storage.yaml
