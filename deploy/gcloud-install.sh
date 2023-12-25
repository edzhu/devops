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
required_services=(
    "compute.googleapis.com"
    "container.googleapis.com"
    "containerregistry.googleapis.com"
    "iam.googleapis.com"
    "cloudbuild.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

usage() {
    echo "Usage: $0 [-s] [-a <service-account>] [-p <project>]"
    echo "  -s: Skip GCloud upgrade"
    echo "  -a: Service account name, default to <${SA_NAME}>"
    echo "  -p: Optional GCloud project name, if set will enable required services in the project"
    exit 1
}

while getopts ":sa:p:" opt; do
    case $opt in
        s)
            SKIP_GCLOUD_UPGRADE=1
            ;;
        a)
            SA_NAME=$OPTARG
            ;;
        p)
            gcloud_project=$OPTARG
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

# Get the latest version of GCloud
latest_version=$(gcloud components list --format json 2> /dev/null |jq -r '.[] |select(.id=="core") |.latest_version_string |select(type=="string")')
if [ -z "${latest_version}" ]; then
    echo "ERROR: Unable to determine locally installed GCloud version!!!"
    echo "See install instructions at https://cloud.google.com/sdk/docs/install-sdk"
    exit 1
fi
echo "Detected latest GCloud CLI version is <${latest_version}>"

# Upgrade GCloud to latest version if installed version is earlier than latest
installed_version=$(gcloud components list --format json 2> /dev/null |jq -r '.[] |select(.id=="core") |.current_version_string |select(type=="string")')
echo "Detected installed GCloud CLI version is <${installed_version}>"
target_version=$(echo -e "${installed_version}\n${latest_version}" |sort --version-sort |tail -n 1)
if [ -z "${target_version}" ]; then
    echo "ERROR: Unable to determine target version of GCloud!!!"
    exit 1
fi
if [ "${installed_version}" != "${target_version}" ]; then
    echo "Upgrading GCloud from ${installed_version} to target release ${target_version}..."
    if [ -z ${SKIP_GCLOUD_UPGRADE+x} ]; then
        gcloud -q components update
        version=$(gcloud components list --format json 2> /dev/null |jq -r '.[] |select(.id=="core") |.current_version_string |select(type=="string")')
        echo "GCloud upgraded to release ${version}"
    else
        echo "Skipping GCloud upgrade due to env flag!"
    fi
fi

# Install gke-gcloud-auth-plugin
is_installed=$(gcloud components list --format json 2> /dev/null |jq -r '.[] |select(.id=="gke-gcloud-auth-plugin") |.state.name')
if [ "${is_installed}" != "Installed" ]; then
    echo "Installing GKE GCLoud authentication plugin..."
    gcloud components install gke-gcloud-auth-plugin --quiet
    version=$(gcloud components list --format json 2> /dev/null |jq -r '.[] |select(.id=="gke-gcloud-auth-plugin") |.current_version_string |select(type=="string")')
    echo "Installed GKE GCloud authentication plugin release ${version}"
fi

# Authorize GCloud if no account is currently active
is_authed=$(gcloud auth list --format json 2> /dev/null |jq -r '.[] |select(.status=="ACTIVE") |.account')
if [ -z "${is_authed}" ]; then
    # Authorize with service account if private key file exists
    sa_key_file="${dir}/../.modules/${ENV}/secret/${SA_NAME}_key.json"
    if [ -f "${sa_key_file}" ]; then
        gcloud auth activate-service-account --key-file="${sa_key_file}"
        echo "Authorized with service account <${SA_NAME}>."
    else
        echo ">>> Authorizing user account..."
        gcloud auth login --no-launch-browser
        echo "<<< User account authorized."
    fi
    is_authed=$(gcloud auth list --format json 2> /dev/null |jq -r '.[] |select(.status=="ACTIVE") |.account')
fi
echo "Authorized GCloud account is <${is_authed}>"

# Perform project specific action if GCloud project is specified
if [ -n "${gcloud_project}" ]; then

    # Make sure GCLoud project is valid
    is_valid=$(gcloud projects list --format json 2> /dev/null |jq -r '.[] |select(.projectId=="'"${gcloud_project}"'") |.projectId')
    if [ -z "${is_valid}" ]; then
        echo "ERROR: Invalid GCloud project <${gcloud_project}>!!!"
        exit 1
    fi

    # Get the list of services already enabled in the GCloud project
    enabled_services=$(gcloud services list --project "${gcloud_project}" --format json 2> /dev/null |jq -r '.[] |select(.state=="ENABLED") |.config.name')

    # Enable required services in GCloud project
    for service in "${required_services[@]}"; do
        is_enabled=$(echo "${enabled_services}" |grep -i "${service}" || true)
        if [ -z "${is_enabled}" ]; then
            echo "Enabling GCloud service <${service}> in project <${gcloud_project}>..."
            gcloud services --project "${gcloud_project}" enable "${service}"
        else
            echo "GCloud service <${service}> already enabled in project <${gcloud_project}>."
        fi
    done

fi
