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

SA_NAME="terraform"

usage() {
    echo "Usage: $0 -e <ops|dev|tst|prd> -p <project> [-a <service-account>]"
    echo "  -a: Service account name, default to <${SA_NAME}>"
    echo "  -e: Environment name"
    echo "  -p: GCloud project name, default to environment variable <GCLOUD_PROJECT>"
    exit 1
}

while getopts ":a:p:e:" opt; do
    case $opt in
        a)
            SA_NAME=$OPTARG
            ;;
        p)
            GCLOUD_PROJECT=$OPTARG
            ;;
        e)
            ENVIRONMENT=$OPTARG
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

# Make sure GCloud project is specified
if [ -z "${GCLOUD_PROJECT}" ]; then
    echo "ERROR: GCloud project name is not specified!!!"
    usage
fi

# Make sure environment is specified and valid
if [ -z "${ENVIRONMENT}" ]; then
    echo "ERROR: Environment name is not specified!!!"
    usage
fi
if [[ "${ENVIRONMENT}" != "ops" && "${ENVIRONMENT}" != "dev" && "${ENVIRONMENT}" != "tst" && "${ENVIRONMENT}" != "prd" ]]; then
    echo "ERROR: Invalid environment name <${ENVIRONMENT}>!!!"
    usage
fi

sa_email="${SA_NAME}@${GCLOUD_PROJECT}.iam.gserviceaccount.com"
sa_path="projects/${GCLOUD_PROJECT}/serviceAccounts/${sa_email}"

# Activate service account if it's already authenticated
is_sa_authed=$(gcloud auth list --format json 2> /dev/null |jq -r '.[] |select(.account=="'"${sa_email}"'")')
if [ -n "${is_sa_authed}" ]; then
    is_sa_active=$(gcloud auth list --format json 2> /dev/null |\
                   jq -r '.[] |select(.account=="'"${sa_email}"'") |select(.status=="ACTIVE")')
    if [ -n "${is_sa_active}" ]; then
        echo "GCloud service account <${SA_NAME}> already activated"
    else
        gcloud config set account "${sa_email}"
        echo "GCloud service account <${SA_NAME}> activated"
    fi
    exit 0
fi

# Create service account if it does not exist
sa_id=$(gcloud --format json iam --project "${GCLOUD_PROJECT}" service-accounts list |\
        jq -r '.[] |select(.name=="'"${sa_path}"'") |select(.disabled==false) |.uniqueId')
if [ -z "${sa_id}" ]; then
    echo "GCloud service account <${SA_NAME}> not found, creating..."
    sa_id=$(gcloud --format json iam --project "${GCLOUD_PROJECT}" service-accounts create "${SA_NAME}" |\
            jq -r '.uniqueId')
    echo "GCloud service account <${SA_NAME}> created with ID ${sa_id}"
fi

# Create service account private access key if one does not already exist
sa_key_file="${dir}/../.modules/${ENVIRONMENT}/secret/${SA_NAME}_key.json"
if ! [ -f "${sa_key_file}" ]; then
    echo "Service account <${SA_NAME}> private access key file not found, creating..."
    gcloud --format json iam --project "${GCLOUD_PROJECT}" service-accounts keys create "${sa_key_file}" --iam-account "${sa_id}"
fi

# Verify private key is associated with the service account
sa_key_id=$(jq -r 'select(.client_email=="'"${sa_email}"'") |.private_key_id |select(type=="string")' "${sa_key_file}" 2> /dev/null || true)
if [ -z "${sa_key_id}" ]; then
    echo "Unable to extract private key ID from file <${sa_key_file}>"
    echo "Delete this file and re-run to create new private key."
    exit 1
fi

# Verify private key is still active in the service account
sa_key_name=$(gcloud --format json iam --project "${GCLOUD_PROJECT}" service-accounts keys list --iam-account "${sa_id}" |\
              jq -r '.[] |select(.name=="'"${sa_path}/keys/${sa_key_id}"'") |.name')
if [ -z "${sa_key_name}" ]; then
    echo "GCloud service account <${SA_NAME}> private access key <${sa_key_id}> not found!!!"
    echo "Delete private key file <${sa_key_file}> and re-run to create new private key."
    exit 2
fi

# Add cluster management permissions to service account
sa_member="serviceAccount:${sa_email}"
is_authed=$(gcloud --format json projects get-iam-policy "${GCLOUD_PROJECT}" |\
            jq -r '.bindings.[] |select(.role=="roles/container.serviceAgent") |.members.[] |select(index("'"${sa_member}"'"))' || true)
if [ -z "${is_authed}" ]; then
    is_authed=$(gcloud projects add-iam-policy-binding "${GCLOUD_PROJECT}" --member "${sa_member}" --role roles/container.serviceAgent |\
                jq -r '.bindings.[] |select(.role=="roles/container.serviceAgent") |.members.[] |select(index("'"${sa_member}"'"))')
    if [ -z "${is_authed}" ]; then
        echo "Failed to bind container.serviceAgent role to <${sa_member}>!!!"
        exit 3
    fi
fi

# Activate the service account
gcloud auth activate-service-account --key-file="${sa_key_file}"
