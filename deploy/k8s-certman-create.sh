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
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Add AWS access credential
. ${dir}/../.modules/${ENV}/secret/aws.cfg
kubectl create secret generic route53-credentials \
        --from-literal=key=${AWS_SECRET_ACCESS_KEY} \
        --dry-run -o yaml -n ${K8S_NAMESPACE} |kubectl apply -f -

# Install or upgrade cert-manager
name=cert-manager
is_installed=$(helm list -n ${K8S_NAMESPACE} |grep ${name} || true)
if [ -z "${is_installed}" ]; then
    helm install ${name} jetstack/cert-manager \
         --namespace ${K8S_NAMESPACE} \
         --create-namespace \
         --set global.leaderElection.namespace=${K8S_NAMESPACE} \
         --set startupapicheck.resources.requests.ephemeral-storage="0.5Gi" \
         --set startupapicheck.resources.requests.memory="0.5Gi" \
         --set startupapicheck.resources.requests.cpu="250m" \
         --set startupapicheck.resources.limits.ephemeral-storage="0.5Gi" \
         --set startupapicheck.resources.limits.memory="0.5Gi" \
         --set startupapicheck.resources.limits.cpu="250m" \
         --set cainjector.resources.requests.ephemeral-storage="0.5Gi" \
         --set cainjector.resources.requests.memory="0.5Gi" \
         --set cainjector.resources.requests.cpu="250m" \
         --set cainjector.resources.limits.ephemeral-storage="0.5Gi" \
         --set cainjector.resources.limits.memory="0.5Gi" \
         --set cainjector.resources.limits.cpu="250m" \
         --set webhook.resources.requests.ephemeral-storage="0.5Gi" \
         --set webhook.resources.requests.memory="0.5Gi" \
         --set webhook.resources.requests.cpu="250m" \
         --set webhook.resources.limits.ephemeral-storage="0.5Gi" \
         --set webhook.resources.limits.memory="0.5Gi" \
         --set webhook.resources.limits.cpu="250m" \
         --set resources.requests.ephemeral-storage="0.5Gi" \
         --set resources.requests.memory="0.5Gi" \
         --set resources.requests.cpu="250m" \
         --set resources.limits.ephemeral-storage="0.5Gi" \
         --set resources.limits.memory="0.5Gi" \
         --set resources.limits.cpu="250m" \
         --set prometheus.enabled=false \
         --set installCRDs=true
else
    helm upgrade ${name} jetstack/cert-manager \
         --namespace ${K8S_NAMESPACE} \
         --set global.leaderElection.namespace=${K8S_NAMESPACE} \
         --set startupapicheck.resources.requests.ephemeral-storage="0.5Gi" \
         --set startupapicheck.resources.requests.memory="0.5Gi" \
         --set startupapicheck.resources.requests.cpu="250m" \
         --set startupapicheck.resources.limits.ephemeral-storage="0.5Gi" \
         --set startupapicheck.resources.limits.memory="0.5Gi" \
         --set startupapicheck.resources.limits.cpu="250m" \
         --set cainjector.resources.requests.ephemeral-storage="0.5Gi" \
         --set cainjector.resources.requests.memory="0.5Gi" \
         --set cainjector.resources.requests.cpu="250m" \
         --set cainjector.resources.limits.ephemeral-storage="0.5Gi" \
         --set cainjector.resources.limits.memory="0.5Gi" \
         --set cainjector.resources.limits.cpu="250m" \
         --set webhook.resources.requests.ephemeral-storage="0.5Gi" \
         --set webhook.resources.requests.memory="0.5Gi" \
         --set webhook.resources.requests.cpu="250m" \
         --set webhook.resources.limits.ephemeral-storage="0.5Gi" \
         --set webhook.resources.limits.memory="0.5Gi" \
         --set webhook.resources.limits.cpu="250m" \
         --set resources.requests.ephemeral-storage="0.5Gi" \
         --set resources.requests.memory="0.5Gi" \
         --set resources.requests.cpu="250m" \
         --set resources.limits.ephemeral-storage="0.5Gi" \
         --set resources.limits.memory="0.5Gi" \
         --set resources.limits.cpu="250m" \
         --set prometheus.enabled=false \
         --set installCRDs=true
fi

# Enable cert-manager issuer
sed "s|{{ aws_access_key_id }}|${AWS_ACCESS_KEY_ID}|g" ${dir}/k8s-certman-issuer.yaml |\
    sed "s|{{ aws_region }}|${AWS_DEFAULT_REGION}|g" |\
    sed "s|{{ namespace }}|${K8S_NAMESPACE}|g" |\
    sed "s|{{ email }}|${AWS_ADMIN_EMAIL}|g" |\
    kubectl apply -f -
