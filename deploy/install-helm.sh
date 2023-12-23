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

# Get latest version of Helm
latest_version=$(curl -s https://get.helm.sh/helm-latest-version)
if [ -z "${latest_version}" ]; then
    echo "Unable to fetch latest version of Helm!!!"
    exit 1
fi

# See if installed version match or is later than latest version
installed_version=$(helm version --template '{{.Version}}' 2> /dev/null || true)
target_version=$(echo -e "${installed_version}\n${latest_version}" |sort --version-sort |tail -n 1)
if [ -z "${target_version}" ]; then
    echo "Unable to determine target version of Helm!!!"
    exit 1
fi
if [ "${installed_version}" != "${target_version}" ]; then
    echo "Upgrading Helm to latest release ${latest_version}..."
    if [ -z ${SKIP_HELM_UPGRADE+x} ]; then
        echo "Skipping Helm upgrade due to env flag!"
    elif [[ "${OSTYPE}" == "linux"* ]]; then
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
    else
        echo "Unsupported OS type <${OSTYPE}>, unable to automatically install Helm."
        echo "See Helm installation instructions at https://helm.sh/docs/intro/install/"
        echo "Set enviroment variable SKIP_HELM_UPGRADE to skip upgrade."
        exit 1
    fi
fi
