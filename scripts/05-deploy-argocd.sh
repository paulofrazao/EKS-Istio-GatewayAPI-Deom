#!/bin/bash
# MTKC POC EKS - Deploy ArgoCD
#
# This script installs ArgoCD using Helm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="argocd"
RELEASE_NAME="argocd"

# Configuration
EXPOSE_TYPE="${1:-LoadBalancer}"  # LoadBalancer or ClusterIP

echo "=== Installing ArgoCD ==="
echo "Namespace: ${NAMESPACE}"
echo "Expose Type: ${EXPOSE_TYPE}"
echo ""

# Add Helm repo
echo "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create namespace
echo "Creating namespace ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD via Helm..."
helm upgrade --install ${RELEASE_NAME} argo/argo-cd \
  --namespace ${NAMESPACE} \
  --set server.service.type=${EXPOSE_TYPE} \
  --set server.extraArgs={--insecure} \
  --set configs.params."server\.insecure"=true \
  --wait

# Wait for deployment
echo ""
echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n ${NAMESPACE} --timeout=120s

# Get admin password
echo ""
echo "=== ArgoCD Credentials ==="
ADMIN_PASSWORD=$(kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Username: admin"
echo "Password: ${ADMIN_PASSWORD}"

# Get access URL
echo ""
echo "=== ArgoCD Access ==="

if [ "${EXPOSE_TYPE}" == "LoadBalancer" ]; then
  echo "Waiting for LoadBalancer to be provisioned..."
  sleep 10

  ARGOCD_URL=$(kubectl get svc argocd-server -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

  if [ -z "$ARGOCD_URL" ]; then
    ARGOCD_URL=$(kubectl get svc argocd-server -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
  fi

  if [ "$ARGOCD_URL" != "pending" ] && [ -n "$ARGOCD_URL" ]; then
    echo "ArgoCD URL: http://${ARGOCD_URL}"
    echo ""
    echo "Login with:"
    echo "  argocd login ${ARGOCD_URL} --username admin --password ${ADMIN_PASSWORD} --insecure"
  else
    echo "LoadBalancer is still provisioning..."
    echo "Run: kubectl get svc argocd-server -n ${NAMESPACE}"
  fi
else
  echo "ArgoCD is exposed as ClusterIP."
  echo ""
  echo "To access ArgoCD, use port-forward:"
  echo "  kubectl port-forward svc/argocd-server -n ${NAMESPACE} 8080:443"
  echo ""
  echo "Then access: https://localhost:8080"
  echo ""
  echo "Login with:"
  echo "  argocd login localhost:8080 --username admin --password ${ADMIN_PASSWORD} --insecure"
fi

echo ""
echo "=== ArgoCD Installation Complete ==="
echo ""
echo "To install ArgoCD CLI (if not installed):"
echo "  brew install argocd"
echo ""
echo "To create an Application:"
echo "  argocd app create <app-name> \\"
echo "    --repo <git-repo-url> \\"
echo "    --path <path-to-manifests> \\"
echo "    --dest-server https://kubernetes.default.svc \\"
echo "    --dest-namespace <namespace>"
