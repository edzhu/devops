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

# Check correct version of Helm is installed
HELM_MIN_VERSION=3
helm_version=$(helm version |awk -Fv '{print $3}' |awk -F. '{print $1}')
if [ ${helm_version} -lt ${HELM_MIN_VERSION} ]; then
    if [[ "${OSTYPE}" == "linux"* ]]; then
        curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | sudo bash
    else
        echo "Helm version ${GCLOUD_MIN_VERSION} or greater is required!!!"
        echo "See instruction at https://helm.sh/docs/intro/install/"
        exit 1
    fi
fi
