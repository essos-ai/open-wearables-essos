#!/usr/bin/env bash
# Builds the backend image, pushes to ECR, and deploys to EKS.
# Mirrors the buildDocker + pushDocker + deployK8s Gradle tasks used for the WAR services.
#
# Usage:
#   ./backend/scripts/deploy.sh           # dev (default)
#   ENV=P ./backend/scripts/deploy.sh     # prod
#
# Requirements: aws CLI, docker, kubectl, envsubst

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${REPO_ROOT}/k8s"
ENV=${ENV:-D}

case "$ENV" in
  D)
    AWS_REGION="us-west-1"
    PLATFORM="linux/amd64"
    K8S_CLUSTER="arn:aws:eks:us-west-1:491085382307:cluster/DevCollaboration1EksCluster"
    ;;
  P)
    AWS_REGION="us-west-2"
    PLATFORM="linux/arm64"
    K8S_CLUSTER="arn:aws:eks:us-west-2:491085382307:cluster/ProdMainEksCluster"
    ;;
  *)
    echo "Unknown ENV: $ENV. Use D (dev) or P (prod)."
    exit 1
    ;;
esac

ACCOUNT_ID="491085382307"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

BUILD_TIMESTAMP="$(date +%Y%m%d%H%M%S)"
GIT_HASH="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
BUILD_TAG="${BUILD_TIMESTAMP}-${GIT_HASH}"
DEPLOY_TAG="${ENV}-${BUILD_TAG}"

IMAGE="${ECR_REGISTRY}/open-wearables/backend:${DEPLOY_TAG}"

echo "==> Build tag: ${DEPLOY_TAG}"

echo "==> Building backend image (${PLATFORM})..."
docker buildx build --platform "${PLATFORM}" --load -t "${IMAGE}" "${BACKEND_DIR}"

echo "==> Authenticating with ECR (${AWS_REGION})..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "==> Pushing image to ECR..."
docker push "${IMAGE}"

echo "==> Switching kubectl context to ${K8S_CLUSTER}..."
kubectl config use-context "${K8S_CLUSTER}"

echo "==> Applying manifests..."
for template in \
  backend-deployment.template.yaml \
  celery-worker-deployment.template.yaml \
  celery-beat-deployment.template.yaml; do
  echo "  Applying ${template}..."
  ACCOUNT_ID="${ACCOUNT_ID}" \
  AWS_REGION="${AWS_REGION}" \
  DEPLOY_TAG="${DEPLOY_TAG}" \
    envsubst < "${K8S_DIR}/${template}" | kubectl apply -f -
done

echo "==> Restarting deployments..."
kubectl rollout restart deployment/backend -n open-wearables
kubectl rollout restart deployment/celery-worker -n open-wearables
kubectl rollout restart deployment/celery-beat -n open-wearables

echo "==> Waiting for backend rollout..."
kubectl rollout status deployment/backend -n open-wearables --timeout=120s

echo "Done. Deployed ${DEPLOY_TAG}."
