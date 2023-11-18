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

# Fetch cert-manager repo
${dir}/install-helm.sh
helm repo add gitlab https://charts.gitlab.io
helm repo update

# Install or upgrade cert-manager
name=gitlab
is_installed=$(helm list -n ${K8S_NAMESPACE} |grep ${name} || true)
. ${dir}/../.modules/${ENV}/secret/config.cfg
if [ -z "${is_installed}" ]; then
    sed -e "s|{{ domain }}|${DOMAIN}|g" \
        -e "s|{{ service_name }}|${name}|g" \
        ${dir}/k8s-gitlab-config.yaml |\
        helm install ${name} --namespace ${K8S_NAMESPACE} \
             -f - gitlab/gitlab
fi
