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

# Delete cert-manager issuer
. ${dir}/../.modules/${ENV}/secret/aws.cfg
sed "s|{{ aws_access_key_id }}|${AWS_ACCESS_KEY_ID}|g" ${dir}/k8s-certman-issuer.yaml |\
    sed "s|{{ aws_region }}|${AWS_DEFAULT_REGION}|g" |\
    sed "s|{{ namespace }}|${K8S_NAMESPACE}|g" |\
    sed "s|{{ email }}|${AWS_ADMIN_EMAIL}|g" |\
    kubectl delete -f - || true

# Delete cert-manager via helm
name=cert-manager
helm --namespace ${K8S_NAMESPACE} delete ${name} || true
