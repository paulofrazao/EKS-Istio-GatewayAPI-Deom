#!/bin/bash
# MTKC POC EKS - Deploy Sample Applications
#
# Prerequisites:
# - EKS cluster created
# - Istio Ambient installed (02-deploy-istio.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"
TF_DIR="${SCRIPT_DIR}/../terraform"

echo "=== Deploying Sample Applications ==="

# Deploy health responder
echo "Deploying health responder..."
kubectl apply -f "${K8S_DIR}/apps/health-responder.yaml"

# Deploy app1
echo "Deploying sample-app-1..."
kubectl apply -f "${K8S_DIR}/apps/app1-deployment.yaml"
kubectl apply -f "${K8S_DIR}/apps/app1-service.yaml"

# Deploy app2
echo "Deploying sample-app-2..."
kubectl apply -f "${K8S_DIR}/apps/app2-deployment.yaml"
kubectl apply -f "${K8S_DIR}/apps/app2-service.yaml"

# Deploy HTTPRoutes
echo "Deploying HTTPRoutes..."
kubectl apply -f "${K8S_DIR}/istio/httproutes.yaml"

# Wait for deployments
echo ""
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/health-responder -n gateway-health --timeout=60s
kubectl rollout status deployment/sample-app-1 -n sample-apps --timeout=60s
kubectl rollout status deployment/sample-app-2 -n sample-apps --timeout=60s

# Show status
echo ""
echo "=== Deployment Status ==="
echo ""
echo "Pods:"
kubectl get pods -n gateway-health
kubectl get pods -n sample-apps

echo ""
echo "Services:"
kubectl get svc -n gateway-health
kubectl get svc -n sample-apps

echo ""
echo "Gateway:"
kubectl get gateway -n istio-ingress

echo ""
echo "HTTPRoutes:"
kubectl get httproute -A

# Get Internal NLB DNS/IP
echo ""
echo "=== Internal NLB Information ==="
echo "Waiting for Internal NLB to be provisioned..."
sleep 15

INTERNAL_NLB_DNS=$(kubectl get svc -n istio-ingress -l istio.io/gateway-name=mtkc-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$INTERNAL_NLB_DNS" ]; then
  echo "Internal NLB DNS: ${INTERNAL_NLB_DNS}"

  # Resolve NLB DNS to IP addresses
  echo ""
  echo "Resolving Internal NLB IPs..."
  INTERNAL_NLB_IPS=$(dig +short ${INTERNAL_NLB_DNS} | head -2)
  echo "Internal NLB IPs: ${INTERNAL_NLB_IPS}"

  # Get ALB target group ARN from Terraform
  echo ""
  echo "=== Updating ALB Target Group ==="
  cd "${TF_DIR}"
  TARGET_GROUP_ARN=$(terraform output -raw alb_target_group_arn 2>/dev/null || echo "")

  if [ -n "$TARGET_GROUP_ARN" ]; then
    echo "Target Group ARN: ${TARGET_GROUP_ARN}"

    # Register Internal NLB IPs with ALB target group
    for IP in ${INTERNAL_NLB_IPS}; do
      echo "Registering IP ${IP} with ALB target group..."
      aws elbv2 register-targets \
        --target-group-arn "${TARGET_GROUP_ARN}" \
        --targets Id="${IP}" || echo "Warning: Failed to register ${IP}"
    done

    echo ""
    echo "ALB Target Group updated successfully!"
  else
    echo "Warning: Could not get ALB target group ARN from Terraform"
    echo "Run manually: aws elbv2 register-targets --target-group-arn <ARN> --targets Id=<NLB_IP>"
  fi
else
  echo "Internal NLB is still provisioning."
  echo "Run the following commands after NLB is ready:"
  echo ""
  echo "1. Get Internal NLB DNS:"
  echo "   kubectl get svc -n istio-ingress -l istio.io/gateway-name=mtkc-gateway"
  echo ""
  echo "2. Resolve to IP:"
  echo "   dig +short <NLB_DNS>"
  echo ""
  echo "3. Update ALB target group:"
  echo "   aws elbv2 register-targets --target-group-arn <TARGET_GROUP_ARN> --targets Id=<NLB_IP>"
fi

# Get ALB DNS for testing
echo ""
echo "=== ALB Information ==="
cd "${TF_DIR}"
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")

if [ -n "$ALB_DNS" ]; then
  echo "ALB DNS: ${ALB_DNS}"
  echo ""
  echo "Test URLs (after ALB target group is updated):"
  echo "  Health:  curl -k https://${ALB_DNS}/healthz/ready"
  echo "  App 1:   curl -k https://${ALB_DNS}/app1"
  echo "  App 2:   curl -k https://${ALB_DNS}/app2"
fi

echo ""
echo "=== Application Deployment Complete ==="
echo ""
echo "Next step: Run 04-validate.sh to test the deployment"
