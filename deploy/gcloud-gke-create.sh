#!/bin/bash -e
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

usage() {
    echo "Usage: $0 -c <cluster> -l <location> -p <project> [-n <namespace>]"
    echo "  -c: Kubernetes cluster name"
    echo "  -l: GCloud location; if a region is specified, a zonal autopilot cluster will be created"
    echo "  -p: GCloud project name"
    echo "  -n: Kubernetes namespace; if specified will create the namespace if it does not exist"
    exit 1
}

while getopts ":c:l:p:n:" opt; do
    case $opt in
        c)
            K8S_CLUSTER=$OPTARG
            ;;
        l)
            GCLOUD_LOCATION=$OPTARG
            ;;
        p)
            GCLOUD_PROJECT=$OPTARG
            ;;
        n)
            K8S_NAMESPACE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

# Make sure GCloud project, GCloud location, and K8S cluster parameters are specified
if [ -z "${GCLOUD_PROJECT}" ] || [ -z "${GCLOUD_LOCATION}" ] || [ -z "${K8S_CLUSTER}" ]; then
    echo "ERROR: GCloud project name, GCloud location, and K8S cluster name are required!!!"
    usage
fi

# If GCloud location is a region, create a zonal autopilot cluster
location_components=$(echo "${GCLOUD_LOCATION}" |awk -F- '{print NF}')
if [ "${location_components}" -eq 3 ]; then
    echo "Requested zonal cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> at <${GCLOUD_LOCATION}>"
    autopilot=false
elif [ "${location_components}" -eq 2 ]; then
    echo "Requested autopilot cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> at <${GCLOUD_LOCATION}>"
    autopilot=true
else
    echo "ERROR: Invalid GCloud location format <${GCLOUD_LOCATION}>"
    exit 1
fi

# Get the autopilot status of the cluster
is_autopilot=$(gcloud --format=json container --project "${GCLOUD_PROJECT}" clusters list |\
               jq '.[] |select(.name=="'"${K8S_CLUSTER}"'") |.autopilot.enabled')

# Create the cluster if it does not exist
if [ -z "${is_autopilot}" ]; then
    if [ "${autopilot}" = true ]; then
        echo "Creating autopilot cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> at <${GCLOUD_LOCATION}>..."
        is_autopilot=$(gcloud --format=json container --project "${GCLOUD_PROJECT}" clusters create-auto \
                       "${K8S_CLUSTER}" --location="${GCLOUD_LOCATION}" |\
                       jq '.[] |select(.name=="'"${K8S_CLUSTER}"'") |.autopilot.enabled')
    else
        echo "Creating zonal cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> at <${GCLOUD_LOCATION}>..."
        is_autopilot=$(gcloud --format=json container --project "${GCLOUD_PROJECT}" clusters create \
                       "${K8S_CLUSTER}" --location="${GCLOUD_LOCATION}" |\
                       jq '.[] |select(.name=="'"${K8S_CLUSTER}"'") |.autopilot.enabled')
    fi
else
    if [ "${autopilot}" = true ]; then
        echo "Autopilot cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> already exists"
    else
        echo "Zonal cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> already exists"
    fi
fi

# Make sure cluster is created and is the correct type
if [ -z "${is_autopilot}" ]; then
    echo "ERROR: Unable to create cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}>!!!"
    exit 1
elif [ "${is_autopilot}" != ${autopilot} ]; then
    if [ "${autopilot}" = true ]; then
        echo "ERROR: Cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> is not an autopilot cluster!!!"
    else
        echo "ERROR: Cluster <${K8S_CLUSTER}> in project <${GCLOUD_PROJECT}> is an autopilot cluster!!!"
    fi
    exit 1
fi

# Setup kubectl authentication
gcloud container clusters get-credentials "${K8S_CLUSTER}" --location="${GCLOUD_LOCATION}" --project="${GCLOUD_PROJECT}"

# Create namespace if it does not exist
if [ -n "${K8S_NAMESPACE}" ]; then
    kubectl get namespace "${K8S_NAMESPACE}" > /dev/null 2>&1 || kubectl create namespace "${K8S_NAMESPACE}"
    kubectl config set-context "$(kubectl config current-context)" --namespace="${K8S_NAMESPACE}"
fi

# Add GKD specific storage classes
kubectl apply -f "${dir}"/k8s-gke-storage.yaml
