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
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install or upgrade ingress-nginx
name=ingress-nginx
is_installed=$(helm list -n ${K8S_NAMESPACE} |grep ${name} || true)
. ${dir}/../.modules/${ENV}/secret/config.cfg
if [ -z "${is_installed}" ]; then
    helm install ${name} ingress-nginx/ingress-nginx \
         --namespace ${K8S_NAMESPACE} \
         --create-namespace \
         --values ${dir}/k8s-nginx-config.yaml \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.memory="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.cpu="250m" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.memory="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.cpu="250m" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.memory="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.cpu="250m" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.memory="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.cpu="250m" \
         --set controller.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.resources.requests.memory="0.5Gi" \
         --set controller.resources.requests.cpu="250m" \
         --set controller.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.resources.limits.memory="0.5Gi" \
         --set controller.resources.limits.cpu="250m" \
         --set controller.replicaCount=${NGINX_REPLICAS} \
         --set controller.allowSnippetAnnotations=true \
         --set controller.service.externalTrafficPolicy=Local
else
    helm upgrade ${name} ingress-nginx/ingress-nginx \
         --namespace ${K8S_NAMESPACE} \
         --create-namespace \
         --values ${dir}/k8s-nginx-config.yaml \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.memory="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.requests.cpu="250m" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.memory="0.5Gi" \
         --set controller.admissionWebhooks.createSecretJob.resources.limits.cpu="250m" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.memory="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.requests.cpu="250m" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.memory="0.5Gi" \
         --set controller.admissionWebhooks.patchWebhookJob.resources.limits.cpu="250m" \
         --set controller.resources.requests.ephemeral-storage="0.5Gi" \
         --set controller.resources.requests.memory="0.5Gi" \
         --set controller.resources.requests.cpu="250m" \
         --set controller.resources.limits.ephemeral-storage="0.5Gi" \
         --set controller.resources.limits.memory="0.5Gi" \
         --set controller.resources.limits.cpu="250m" \
         --set controller.replicaCount=${NGINX_REPLICAS} \
         --set controller.allowSnippetAnnotations=true \
         --set controller.service.externalTrafficPolicy=Local
fi
