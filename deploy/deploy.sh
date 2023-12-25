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

"${dir}"/gcloud-install.sh -p "${GCLOUD_PROJECT}"
"${dir}"/gcloud-sa-create.sh -p "${GCLOUD_PROJECT}" -e "${ENV}"
"${dir}"/gcloud-gke-create.sh -p "${GCLOUD_PROJECT}" -c "${K8S_CLUSTER}" -l "${GCLOUD_LOCATION}" -n "${K8S_NAMESPACE}"


#${dir}/k8s-nginx-create.sh
#${dir}/k8s-certman-create.sh
