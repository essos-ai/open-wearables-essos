#!/usr/bin/env bash
# Creates (or updates) the open-wearables Kubernetes secret from AWS Secrets Manager.
# Run any time secrets change. Also called automatically by deploy.sh.
#
# Usage:
#   ./k8s/create-secret.sh           # dev (default)
#   ENV=P ./k8s/create-secret.sh     # prod
#
# Requirements: aws CLI, kubectl, jq

set -euo pipefail

ENV=${ENV:-D}

case "$ENV" in
  D)
    REGION="us-west-1"
    SECRET_ID="open-wearables/dev"
    ;;
  P)
    REGION="us-west-2"
    SECRET_ID="open-wearables/prod"
    ;;
  *)
    echo "Unknown ENV: $ENV. Use D (dev) or P (prod)."
    exit 1
    ;;
esac

K8S_SECRET_NAME="open-wearables"
NAMESPACE="open-wearables"

echo "Fetching ${SECRET_ID} from Secrets Manager (${REGION})..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --region "${REGION}" \
  --secret-id "${SECRET_ID}" \
  --query SecretString \
  --output text)

echo "Creating/updating Kubernetes secret '${K8S_SECRET_NAME}' in namespace '${NAMESPACE}'..."

LITERAL_ARGS=()
while IFS= read -r line; do
  LITERAL_ARGS+=("$line")
done < <(echo "${SECRET_JSON}" | jq -r 'to_entries[] | "--from-literal=\(.key)=\(.value)"')

kubectl create secret generic "${K8S_SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  "${LITERAL_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done."
